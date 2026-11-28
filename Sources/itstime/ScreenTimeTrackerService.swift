import Foundation
import AppKit
import Combine
import CoreGraphics
import CoreAudio

@MainActor
public final class ScreenTimeTrackerService: ObservableObject {
    public static let shared = ScreenTimeTrackerService()
    
    // MARK: - 常量配置
    /// 闲置超时阈值：5 分钟（300 秒）无操作判定为闲置
    public static let idleThresholdSeconds: TimeInterval = 300.0
    /// 活跃状态下的心跳检测间隔：5 秒（带容差，最大化能效与合流）
    private static let activeHeartbeatInterval: TimeInterval = 5.0
    /// 闲置状态下的心跳检测间隔：15 秒（降频节约能耗）
    private static let idleHeartbeatInterval: TimeInterval = 15.0
    
    private let storageKeyPrefix = "ItsTime_ScreenTime_"
    private let recordedDatesKey = "ItsTime_ScreenTime_RecordedDates"
    private let trackingEnabledKey = "ItsTime_ScreenTime_Enabled"
    
    /// 屏幕时间独立文件存储目录（测试环境下隔离至临时目录，避免污染或读取真实用户数据）
    private var storageDirectory: URL {
        if NSClassFromString("XCTestCase") != nil ||
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ItsTimeTests_ScreenTime", isDirectory: true)
            if !FileManager.default.fileExists(atPath: dir.path) {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            return dir
        }
        return AppPreferences.appSupportDirectory(subpath: "ScreenTime")
    }
    
    // MARK: - 发布的响应式状态
    /// 今日总活跃屏幕时长（秒）
    @Published public private(set) var todayTotalSeconds: TimeInterval = 0
    /// 今日亮屏闲置时长（秒）
    @Published public private(set) var todayIdleSeconds: TimeInterval = 0
    
    /// 当前选中的时间统计维度（日 / 周 / 月 / 年）
    @Published public var selectedScope: TimeScope = .day {
        didSet {
            refreshStats()
        }
    }
    
    /// 统计锚点日期（默认今天）
    @Published public var anchorDate: Date = Date() {
        didSet {
            refreshStats()
        }
    }
    
    /// 当前时间维度下的聚合统计结果
    @Published public private(set) var currentStats: AggregatedScreenTimeStats = AggregatedScreenTimeStats(scope: .day)
    
    /// 今日各应用使用时长列表（按时长降序）
    @Published public private(set) var todaySortedApps: [AppUsageRecord] = []
    /// 今日各事件/定时任务触发列表（按触发次数降序）
    @Published public private(set) var todaySortedEventTriggers: [EventTriggerRecord] = []
    /// 今日事件累计触发的总次数
    @Published public private(set) var todayTotalEventTriggerCount: Int = 0
    /// 当前前台应用信息
    @Published public private(set) var currentForegroundApp: (name: String, bundleId: String)? = nil
    /// 当前用户是否处于无操作闲置状态（超过 5 分钟）
    @Published public private(set) var isUserIdle: Bool = false
    /// 当前是否处于不可计时状态（息屏、锁屏、休眠或闲置）
    @Published public private(set) var isPausedState: Bool = false
    /// 是否开启屏幕时间追踪
    @Published public var isTrackingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isTrackingEnabled, forKey: trackingEnabledKey)
            if isTrackingEnabled {
                startTrackingTimer()
            } else {
                stopTrackingTimer()
            }
            updatePausedState()
        }
    }
    
    /// 简要格式化文本（如 "1h 24m" 或 "15m"）
    public var formattedTodayDuration: String {
        let total = Int(todayTotalSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    // MARK: - 内部追踪状态
    private var todayRecord: DailyScreenTimeRecord
    private var trackingTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    
    /// 上次有效计算的时间戳（基于时间差 Delta 准确计算，杜绝单秒 Tick 唤醒能耗）
    internal var lastActiveTimestamp: Date = Date()
    private var lastSaveDate: Date = Date()
    
    /// 供测试注入的扬声器活跃状态覆盖
    internal var isAudioOutputActiveOverride: (() -> Bool)?
    
    private var isScreenAsleep: Bool = false
    private var isScreenLocked: Bool = false
    private var isSystemSleeping: Bool = false
    
    private var iconCache: [String: NSImage] = [:]
    
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
    
    public init() {
        let enabled = UserDefaults.standard.object(forKey: trackingEnabledKey) as? Bool ?? true
        self.isTrackingEnabled = enabled
        
        let todayStr = Self.dateFormatter.string(from: Date())
        self.todayRecord = DailyScreenTimeRecord(dateString: todayStr)
        
        migrateLegacyUserDefaultsRecordsIfNeeded()
        loadTodayRecord()
        setupNotifications()
        updateCurrentForegroundApp(isInitial: true)
        
        if enabled {
            startTrackingTimer()
        }
        refreshStats()
    }
    
    deinit {
        trackingTimer?.invalidate()
        trackingTimer = nil
        for obs in observers {
            NotificationCenter.default.removeObserver(obs)
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            DistributedNotificationCenter.default().removeObserver(obs)
        }
    }
    
    // MARK: - 能耗优化：智能心跳定时器控制
    /// 启动低频心跳定时器（5秒间隔，带 1.0 秒系统合流容差，大幅减少 CPU 唤醒）
    private func startTrackingTimer(interval: TimeInterval? = nil, resetTimestamp: Bool = true) {
        stopTrackingTimer()
        if resetTimestamp {
            lastActiveTimestamp = Date()
        }
        let heartbeat = interval ?? Self.activeHeartbeatInterval
        
        let timer = Timer(timeInterval: heartbeat, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.heartbeatTick()
            }
        }
        // 允许系统根据电源管理策略在 1 秒容差内合流唤醒，极大提升 Apple Silicon 能效
        timer.tolerance = 1.0
        RunLoop.main.add(timer, forMode: .common)
        self.trackingTimer = timer
    }
    
    /// 停止定时器（息屏、锁屏、休眠时彻底销毁定时器，实现后台 0 CPU 占用）
    private func stopTrackingTimer() {
        trackingTimer?.invalidate()
        trackingTimer = nil
    }
    
    // MARK: - 监听通知设置
    private func setupNotifications() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        
        // 1. 前台应用切换（事件驱动，切换时立刻结算上一应用的流逝时长）
        let appObserver = wsCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            Task { @MainActor [weak self] in
                self?.handleAppActivated(notification: notif)
            }
        }
        observers.append(appObserver)
        
        // 2. 屏幕息屏与亮屏（息屏彻底停用定时器，亮屏恢复）
        let screenSleep = wsCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.commitDeltaDuration()
                self?.isScreenAsleep = true
                self?.stopTrackingTimer() // 息屏停用定时器，零能耗
                self?.updatePausedState()
            }
        }
        let screenWake = wsCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isScreenAsleep = false
                self?.lastActiveTimestamp = Date()
                if self?.isTrackingEnabled == true {
                    self?.startTrackingTimer()
                }
                self?.updatePausedState()
            }
        }
        observers.append(contentsOf: [screenSleep, screenWake])
        
        // 3. 锁屏与解锁（锁屏彻底停用定时器）
        let distCenter = DistributedNotificationCenter.default()
        let lockObserver = distCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.commitDeltaDuration()
                self?.isScreenLocked = true
                self?.stopTrackingTimer() // 锁屏停用定时器，零能耗
                self?.updatePausedState()
            }
        }
        let unlockObserver = distCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isScreenLocked = false
                self?.lastActiveTimestamp = Date()
                if self?.isTrackingEnabled == true {
                    self?.startTrackingTimer()
                }
                self?.updatePausedState()
            }
        }
        observers.append(contentsOf: [lockObserver, unlockObserver])
        
        // 4. 系统休眠与唤醒
        let sysSleep = wsCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.commitDeltaDuration()
                self?.isSystemSleeping = true
                self?.stopTrackingTimer()
                self?.saveTodayRecord(force: true)
                self?.updatePausedState()
            }
        }
        let sysWake = wsCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isSystemSleeping = false
                self?.lastActiveTimestamp = Date()
                self?.checkDateRollOver()
                if self?.isTrackingEnabled == true {
                    self?.startTrackingTimer()
                }
                self?.updatePausedState()
            }
        }
        observers.append(contentsOf: [sysSleep, sysWake])
        
        // 5. 应用退出前持久化刷盘
        let termObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.commitDeltaDuration()
                self?.saveTodayRecord(force: true)
            }
        }
        observers.append(termObserver)
    }
    
    // MARK: - 计时与增量计算
    private func heartbeatTick() {
        guard isTrackingEnabled else { return }
        checkDateRollOver()
        
        let idleSeconds = getSystemIdleSeconds()
        let isPlayingAudio = isAudioOutputActiveOverride?() ?? isAudioOutputActive()
        processHeartbeat(idleSeconds: idleSeconds, isPlayingAudio: isPlayingAudio)
        
        // 批量防抖持久化（每 60 秒刷盘一次，大幅减少磁盘 I/O）
        if Date().timeIntervalSince(lastSaveDate) >= 60.0 {
            saveTodayRecord(force: false)
        }
    }
    
    /// 根据无操作秒数与扬声器状态更新活跃/闲置状态并结算时间增量
    internal func processHeartbeat(idleSeconds: TimeInterval, isPlayingAudio: Bool, now: Date = Date()) {
        guard isTrackingEnabled else { return }
        let wasIdle = isUserIdle
        // 正在通过扬声器播放音视频时，视为活跃状态，不判定为闲置
        isUserIdle = (idleSeconds >= Self.idleThresholdSeconds) && !isPlayingAudio
        
        // 闲置状态自适应降频调度（保留当前时间戳，不丢失切换瞬间的差值）
        if isUserIdle != wasIdle {
            startTrackingTimer(
                interval: isUserIdle ? Self.idleHeartbeatInterval : Self.activeHeartbeatInterval,
                resetTimestamp: false
            )
        }
        
        updatePausedState()
        
        if !isScreenOrSessionLocked {
            if !isUserIdle {
                commitDeltaDuration(now: now)
            } else {
                commitIdleDeltaDuration(now: now)
            }
        } else {
            lastActiveTimestamp = now
        }
    }
    
    /// 计算并消费自上次结算以来的有效时间差（过滤异常跳跃）
    private func consumeValidDelta(now: Date = Date()) -> TimeInterval? {
        let delta = now.timeIntervalSince(lastActiveTimestamp)
        lastActiveTimestamp = now
        // 容错：增量小于 0.1 秒或大于 60 秒（如休眠唤醒缝隙），安全忽略
        guard delta >= 0.1 && delta <= 60.0 else { return nil }
        return delta
    }
    
    /// 将上次计算至今的时间差（Delta）结算给当前活跃应用
    private func commitDeltaDuration(now: Date = Date()) {
        guard let delta = consumeValidDelta(now: now) else { return }
        guard !isScreenOrSessionLocked && !isUserIdle && isTrackingEnabled else { return }
        
        if currentForegroundApp == nil {
            updateCurrentForegroundApp(isInitial: false)
        }
        guard let app = currentForegroundApp else { return }
        
        todayRecord.totalActiveSeconds += delta
        var record = todayRecord.appUsages[app.bundleId] ?? AppUsageRecord(
            bundleIdentifier: app.bundleId,
            appName: app.name,
            durationSeconds: 0,
            activationCount: 1,
            lastActiveDate: now
        )
        record.appName = app.name
        record.durationSeconds += delta
        record.lastActiveDate = now
        todayRecord.appUsages[app.bundleId] = record
        
        todayTotalSeconds = todayRecord.totalActiveSeconds
        todaySortedApps = todayRecord.sortedApps
        
        if selectedScope == .day {
            refreshStats()
        }
    }
    
    /// 将亮屏但无操作的闲置时间结算给今日亮屏闲置时长
    private func commitIdleDeltaDuration(now: Date = Date()) {
        guard let delta = consumeValidDelta(now: now) else { return }
        guard !isScreenOrSessionLocked && isUserIdle && isTrackingEnabled else { return }
        
        todayRecord.totalIdleSeconds += delta
        todayIdleSeconds = todayRecord.totalIdleSeconds
        
        if selectedScope == .day {
            refreshStats()
        }
    }
    
    /// 查询默认音频输出设备（扬声器/耳机）是否正在播放音频
    public func isAudioOutputActive() -> Bool {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var deviceSize = UInt32(MemoryLayout<AudioObjectID>.size)
        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress,
            0,
            nil,
            &deviceSize,
            &deviceID
        )
        guard status == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else {
            return false
        }
        
        var isRunning: UInt32 = 0
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let runningStatus = AudioObjectGetPropertyData(
            deviceID,
            &runningAddress,
            0,
            nil,
            &runningSize,
            &isRunning
        )
        return runningStatus == noErr && isRunning != 0
    }
    
    public func getSystemIdleSeconds() -> TimeInterval {
        let seconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0)!
        )
        return seconds
    }
    
    /// 实时查询系统原生显示器息屏与锁屏会话状态
    public var isScreenOrSessionLocked: Bool {
        if isScreenAsleep || isScreenLocked || isSystemSleeping {
            return true
        }
        if CGDisplayIsAsleep(CGMainDisplayID()) != 0 {
            return true
        }
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any],
           let locked = session["CGSSessionScreenIsLocked"] as? Bool, locked {
            return true
        }
        return false
    }
    
    private func updatePausedState() {
        let paused = isScreenOrSessionLocked || isUserIdle || !isTrackingEnabled
        if isPausedState != paused {
            isPausedState = paused
        }
    }
    
    private func handleAppActivated(notification: Notification) {
        // 先结算前一个 App 的时间差
        commitDeltaDuration()
        
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            guard isValidTrackableApp(app) else { return }
            let bundleId = app.bundleIdentifier ?? "unknown.process.\(app.processIdentifier)"
            let name = app.localizedName ?? "未知应用"
            applyAppSwitch(name: name, bundleId: bundleId)
        } else {
            updateCurrentForegroundApp(isInitial: false)
        }
    }
    
    private func updateCurrentForegroundApp(isInitial: Bool) {
        if let activeApp = NSWorkspace.shared.frontmostApplication {
            guard isValidTrackableApp(activeApp) else { return }
            let bundleId = activeApp.bundleIdentifier ?? "unknown.process.\(activeApp.processIdentifier)"
            let name = activeApp.localizedName ?? "未知应用"
            if isInitial {
                self.currentForegroundApp = (name: name, bundleId: bundleId)
            } else {
                applyAppSwitch(name: name, bundleId: bundleId)
            }
        }
    }
    
    private func isValidTrackableApp(_ app: NSRunningApplication) -> Bool {
        guard app.activationPolicy == .regular else { return false }
        guard let bundleId = app.bundleIdentifier, !bundleId.isEmpty else { return false }
        let ignoredPrefixes = [
            "com.apple.loginwindow",
            "com.apple.dock",
            "com.apple.WindowManager",
            "com.apple.controlcenter",
            "com.apple.notificationcenterui",
            "com.apple.Spotlight",
            "com.apple.QuickLookUIService"
        ]
        return !ignoredPrefixes.contains(where: { bundleId.hasPrefix($0) })
    }
    
    private func applyAppSwitch(name: String, bundleId: String) {
        let isDifferentApp = currentForegroundApp?.bundleId != bundleId
        self.currentForegroundApp = (name: name, bundleId: bundleId)
        
        if isDifferentApp && isTrackingEnabled {
            var record = todayRecord.appUsages[bundleId] ?? AppUsageRecord(
                bundleIdentifier: bundleId,
                appName: name,
                durationSeconds: 0,
                activationCount: 0,
                lastActiveDate: Date()
            )
            record.activationCount += 1
            record.appName = name
            record.lastActiveDate = Date()
            todayRecord.appUsages[bundleId] = record
            
            todaySortedApps = todayRecord.sortedApps
            if selectedScope == .day {
                refreshStats()
            }
        }
    }
    
    // MARK: - 事件触发次数统计
    @discardableResult
    public func recordEventTrigger(for task: ScheduleTask) -> UUID? {
        // 息屏、锁屏或系统休眠时绝不计入统计
        guard !isScreenOrSessionLocked else { return nil }
        
        let now = Date()
        var event = todayRecord.eventTriggers[task.id] ?? EventTriggerRecord(
            id: task.id,
            taskName: task.name,
            triggerTypeTitle: task.trigger.displayTitle,
            count: 0,
            lastTriggeredAt: now
        )
        event.count += 1
        event.taskName = task.name
        event.triggerTypeTitle = task.trigger.displayTitle
        event.lastTriggeredAt = now
        todayRecord.eventTriggers[task.id] = event
        
        // 记录单次流水日志（用于时间带展现已发生事件）
        let kindStr: String
        switch task.trigger {
        case .countdown: kindStr = "countdown"
        case .daily: kindStr = "daily"
        case .interval: kindStr = "interval"
        case .once: kindStr = "once"
        }
        let logItem = PastEventLogItem(
            taskId: task.id,
            taskName: task.name,
            triggerTypeTitle: task.trigger.displayTitle,
            timestamp: now,
            kindString: kindStr,
            actionDesc: task.action.summary
        )
        if todayRecord.pastEventLogs == nil {
            todayRecord.pastEventLogs = []
        }
        todayRecord.pastEventLogs?.append(logItem)
        
        todaySortedEventTriggers = todayRecord.sortedEventTriggers
        todayTotalEventTriggerCount = todayRecord.totalEventTriggerCount
        refreshStats()
        saveTodayRecord(force: true)
        return logItem.id
    }
    
    /// 将指定触发流水标记为「已忽略」（表示用户未执行），并同步累加对应任务的忽略次数
    public func markEventLogIgnored(logId: UUID) {
        if let idx = todayRecord.pastEventLogs?.firstIndex(where: { $0.id == logId }) {
            guard !(todayRecord.pastEventLogs?[idx].effectiveIsIgnored ?? false) else { return }
            todayRecord.pastEventLogs?[idx].isIgnored = true
            if let taskId = todayRecord.pastEventLogs?[idx].taskId,
               var ev = todayRecord.eventTriggers[taskId] {
                ev.ignoredCount = ev.effectiveIgnoredCount + 1
                todayRecord.eventTriggers[taskId] = ev
            }
            todaySortedEventTriggers = todayRecord.sortedEventTriggers
            refreshStats()
            saveTodayRecord(force: true)
            return
        }
        
        // 跨日兜底：若弹窗跨过零点才被点击忽略，尝试在昨日记录中定位并更新
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) {
            let yesterdayStr = Self.dateFormatter.string(from: yesterday)
            if var record = loadRecord(for: yesterdayStr),
               let idx = record.pastEventLogs?.firstIndex(where: { $0.id == logId }) {
                guard !(record.pastEventLogs?[idx].effectiveIsIgnored ?? false) else { return }
                record.pastEventLogs?[idx].isIgnored = true
                if let taskId = record.pastEventLogs?[idx].taskId,
                   var ev = record.eventTriggers[taskId] {
                    ev.ignoredCount = ev.effectiveIgnoredCount + 1
                    record.eventTriggers[taskId] = ev
                }
                let fileURL = recordFileURL(for: yesterdayStr)
                if let data = try? JSONEncoder().encode(record) {
                    try? data.write(to: fileURL, options: .atomic)
                }
                refreshStats()
            }
        }
    }
    
    // MARK: - 日期导航与周期判断
    /// 能否向未来翻页（不可超过当前系统时间对应的周期）
    public var canGoNext: Bool {
        let now = Date()
        let calendar = Calendar.current
        switch selectedScope {
        case .day:
            return calendar.startOfDay(for: anchorDate) < calendar.startOfDay(for: now)
        case .week:
            let compAnchor = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: anchorDate)
            let compNow = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            guard let y1 = compAnchor.yearForWeekOfYear, let w1 = compAnchor.weekOfYear,
                  let y2 = compNow.yearForWeekOfYear, let w2 = compNow.weekOfYear else { return false }
            return (y1 < y2) || (y1 == y2 && w1 < w2)
        case .month:
            let compAnchor = calendar.dateComponents([.year, .month], from: anchorDate)
            let compNow = calendar.dateComponents([.year, .month], from: now)
            guard let y1 = compAnchor.year, let m1 = compAnchor.month,
                  let y2 = compNow.year, let m2 = compNow.month else { return false }
            return (y1 < y2) || (y1 == y2 && m1 < m2)
        case .year:
            let y1 = calendar.component(.year, from: anchorDate)
            let y2 = calendar.component(.year, from: now)
            return y1 < y2
        }
    }
    
    /// 当前锚点是否就是当前周期
    public var isCurrentPeriod: Bool {
        !canGoNext
    }
    
    /// 向过去翻一个周期
    public func goToPrevious() {
        let calendar = Calendar.current
        switch selectedScope {
        case .day:
            if let prev = calendar.date(byAdding: .day, value: -1, to: anchorDate) {
                anchorDate = prev
            }
        case .week:
            if let prev = calendar.date(byAdding: .weekOfYear, value: -1, to: anchorDate) {
                anchorDate = prev
            }
        case .month:
            if let prev = calendar.date(byAdding: .month, value: -1, to: anchorDate) {
                anchorDate = prev
            }
        case .year:
            if let prev = calendar.date(byAdding: .year, value: -1, to: anchorDate) {
                anchorDate = prev
            }
        }
    }
    
    /// 向后翻一个周期（若已经是当前周期则不操作）
    public func goToNext() {
        guard canGoNext else { return }
        let calendar = Calendar.current
        let now = Date()
        var nextDate: Date? = nil
        switch selectedScope {
        case .day:
            nextDate = calendar.date(byAdding: .day, value: 1, to: anchorDate)
        case .week:
            nextDate = calendar.date(byAdding: .weekOfYear, value: 1, to: anchorDate)
        case .month:
            nextDate = calendar.date(byAdding: .month, value: 1, to: anchorDate)
        case .year:
            nextDate = calendar.date(byAdding: .year, value: 1, to: anchorDate)
        }
        if let next = nextDate {
            anchorDate = min(next, now)
        }
    }
    
    /// 回到今天/当前周期
    public func goToToday() {
        anchorDate = Date()
    }
    
    /// 选择具体日期
    public func selectDate(_ date: Date) {
        let now = Date()
        anchorDate = min(date, now)
    }
    
    /// 当前周期的显示标题（纯粹无冗余，如 "11月24日"、"11月"、"2026年"）
    public var periodTitle: String {
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedScope {
        case .day:
            let df = DateFormatter()
            if calendar.component(.year, from: anchorDate) == calendar.component(.year, from: now) {
                df.dateFormat = "M月d日"
            } else {
                df.dateFormat = "yyyy年M月d日"
            }
            df.locale = Locale(identifier: "zh_CN")
            return df.string(from: anchorDate)
            
        case .week:
            var startOfWeek = anchorDate
            var interval: TimeInterval = 0
            _ = calendar.dateInterval(of: .weekOfYear, start: &startOfWeek, interval: &interval, for: anchorDate)
            let endOfWeek = startOfWeek.addingTimeInterval(interval - 1)
            let df = DateFormatter()
            df.dateFormat = "M/d"
            let startStr = df.string(from: startOfWeek)
            let endStr = df.string(from: endOfWeek)
            let weekNum = calendar.component(.weekOfYear, from: anchorDate)
            let year = calendar.component(.yearForWeekOfYear, from: anchorDate)
            
            if calendar.component(.year, from: anchorDate) == calendar.component(.year, from: now) {
                return "\(startStr) - \(endStr)"
            } else {
                return "\(year)年 第\(weekNum)周 (\(startStr) - \(endStr))"
            }
            
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: anchorDate)
            let currentComps = calendar.dateComponents([.year, .month], from: now)
            if comps.year == currentComps.year {
                return "\(comps.month ?? 1)月"
            } else {
                return "\(comps.year ?? 2026)年\(comps.month ?? 1)月"
            }
            
        case .year:
            let y = calendar.component(.year, from: anchorDate)
            return "\(y)年"
        }
    }
    
    // MARK: - 日 / 周 / 月 / 年 聚合计算引擎
    public func refreshStats() {
        self.currentStats = calculateStats(for: selectedScope, anchor: anchorDate)
    }
    
    public func calculateStats(for scope: TimeScope, anchor: Date? = nil) -> AggregatedScreenTimeStats {
        let targetAnchor = anchor ?? anchorDate
        let now = Date()
        let calendar = Calendar.current
        
        switch scope {
        case .day:
            if calendar.isDateInToday(targetAnchor) {
                return AggregatedScreenTimeStats(
                    scope: .day,
                    totalActiveSeconds: todayRecord.totalActiveSeconds,
                    totalIdleSeconds: todayRecord.totalIdleSeconds,
                    sortedApps: todayRecord.sortedApps,
                    sortedEventTriggers: todayRecord.sortedEventTriggers,
                    totalEventTriggerCount: todayRecord.totalEventTriggerCount,
                    periodDescription: periodTitle,
                    dailyAverageSeconds: todayRecord.totalActiveSeconds,
                    pastEventLogs: todayRecord.pastEventLogs ?? []
                )
            } else {
                let targetDateStr = Self.dateFormatter.string(from: targetAnchor)
                if let record = loadRecord(for: targetDateStr) {
                    return AggregatedScreenTimeStats(
                        scope: .day,
                        totalActiveSeconds: record.totalActiveSeconds,
                        totalIdleSeconds: record.totalIdleSeconds,
                        sortedApps: record.sortedApps,
                        sortedEventTriggers: record.sortedEventTriggers,
                        totalEventTriggerCount: record.totalEventTriggerCount,
                        periodDescription: periodTitle,
                        dailyAverageSeconds: record.totalActiveSeconds,
                        pastEventLogs: record.pastEventLogs ?? []
                    )
                } else {
                    return AggregatedScreenTimeStats(
                        scope: .day,
                        totalActiveSeconds: 0,
                        totalIdleSeconds: 0,
                        sortedApps: [],
                        sortedEventTriggers: [],
                        totalEventTriggerCount: 0,
                        periodDescription: periodTitle,
                        dailyAverageSeconds: 0,
                        pastEventLogs: []
                    )
                }
            }
            
        case .week:
            var startOfWeek = targetAnchor
            var interval: TimeInterval = 0
            _ = calendar.dateInterval(of: .weekOfYear, start: &startOfWeek, interval: &interval, for: targetAnchor)
            let endOfWeek = startOfWeek.addingTimeInterval(interval - 1)
            let effectiveEnd = min(endOfWeek, now)
            let dates = getDatesBetween(start: startOfWeek, end: effectiveEnd)
            let records = loadRecords(for: dates)
            let buckets = buildWeekBuckets(startOfWeek: startOfWeek, records: records, calendar: calendar)
            return aggregate(records: records, scope: .week, periodDescription: periodTitle, buckets: buckets)
            
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: targetAnchor)
            let startOfMonth = calendar.date(from: comps) ?? targetAnchor
            guard let range = calendar.range(of: .day, in: .month, for: startOfMonth),
                  let endOfMonth = calendar.date(byAdding: .day, value: range.count - 1, to: startOfMonth) else {
                let dates = [Self.dateFormatter.string(from: targetAnchor)]
                let records = loadRecords(for: dates)
                return aggregate(records: records, scope: .month, periodDescription: periodTitle)
            }
            let effectiveEnd = min(endOfMonth, now)
            let dates = getDatesBetween(start: startOfMonth, end: effectiveEnd)
            let records = loadRecords(for: dates)
            let buckets = buildMonthBuckets(startOfMonth: startOfMonth, daysCount: range.count, records: records, calendar: calendar)
            return aggregate(records: records, scope: .month, periodDescription: periodTitle, buckets: buckets)
            
        case .year:
            let comps = calendar.dateComponents([.year], from: targetAnchor)
            let targetYear = comps.year ?? calendar.component(.year, from: now)
            let startOfYear = calendar.date(from: comps) ?? targetAnchor
            let compsNext = DateComponents(year: targetYear + 1, month: 1, day: 1)
            let startOfNextYear = calendar.date(from: compsNext) ?? targetAnchor
            let endOfYear = calendar.date(byAdding: .day, value: -1, to: startOfNextYear) ?? targetAnchor
            let effectiveEnd = min(endOfYear, now)
            let dates = getDatesBetween(start: startOfYear, end: effectiveEnd)
            let records = loadRecords(for: dates)
            let buckets = buildYearBuckets(year: targetYear, records: records, calendar: calendar)
            return aggregate(records: records, scope: .year, periodDescription: periodTitle, buckets: buckets)
        }
    }
    
    private func buildWeekBuckets(startOfWeek: Date, records: [DailyScreenTimeRecord], calendar: Calendar) -> [ScreenTimeBucket] {
        let recordMap = Dictionary(uniqueKeysWithValues: records.map { ($0.dateString, $0.totalActiveSeconds) })
        let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]
        let df = DateFormatter()
        df.dateFormat = "M月d日"
        
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startOfWeek) else { return nil }
            let dateStr = Self.dateFormatter.string(from: date)
            let weekdayIdx = max(0, min(6, calendar.component(.weekday, from: date) - 1))
            let symbol = weekdaySymbols[weekdayIdx]
            return ScreenTimeBucket(
                id: dateStr,
                label: symbol,
                fullLabel: "\(df.string(from: date)) 周\(symbol)",
                durationSeconds: recordMap[dateStr] ?? 0,
                date: date
            )
        }
    }
    
    private func buildMonthBuckets(startOfMonth: Date, daysCount: Int, records: [DailyScreenTimeRecord], calendar: Calendar) -> [ScreenTimeBucket] {
        let recordMap = Dictionary(uniqueKeysWithValues: records.map { ($0.dateString, $0.totalActiveSeconds) })
        let df = DateFormatter()
        df.dateFormat = "M月d日"
        
        return (0..<daysCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startOfMonth) else { return nil }
            let dateStr = Self.dateFormatter.string(from: date)
            let day = calendar.component(.day, from: date)
            return ScreenTimeBucket(
                id: dateStr,
                label: "\(day)",
                fullLabel: df.string(from: date),
                durationSeconds: recordMap[dateStr] ?? 0,
                date: date
            )
        }
    }
    
    private func buildYearBuckets(year: Int, records: [DailyScreenTimeRecord], calendar: Calendar) -> [ScreenTimeBucket] {
        var monthTotals: [Int: TimeInterval] = [:]
        for record in records {
            let parts = record.dateString.split(separator: "-")
            if parts.count >= 2, let m = Int(parts[1]) {
                monthTotals[m, default: 0] += record.totalActiveSeconds
            }
        }
        
        return (1...12).compactMap { month in
            let comps = DateComponents(year: year, month: month, day: 1)
            guard let date = calendar.date(from: comps) else { return nil }
            let id = String(format: "%04d-%02d", year, month)
            return ScreenTimeBucket(
                id: id,
                label: "\(month)月",
                fullLabel: "\(year)年\(month)月",
                durationSeconds: monthTotals[month] ?? 0,
                date: date
            )
        }
    }
    
    private func getDatesBetween(start: Date, end: Date) -> [String] {
        var dates: [String] = []
        var current = Calendar.current.startOfDay(for: start)
        let endDay = Calendar.current.startOfDay(for: end)
        
        while current <= endDay {
            dates.append(Self.dateFormatter.string(from: current))
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return dates
    }
    
    private func loadRecords(for dateStrings: [String]) -> [DailyScreenTimeRecord] {
        var list: [DailyScreenTimeRecord] = []
        for d in dateStrings {
            if d == todayRecord.dateString {
                list.append(todayRecord)
            } else if let record = loadRecord(for: d) {
                list.append(record)
            }
        }
        return list
    }
    
    private func recordFileURL(for dateString: String) -> URL {
        storageDirectory.appendingPathComponent("\(dateString).json")
    }
    
    private func migrateLegacyUserDefaultsRecordsIfNeeded() {
        let defaults = UserDefaults.standard
        let recordedDates = defaults.stringArray(forKey: recordedDatesKey) ?? []
        var keysToRemove: [String] = []
        
        for dateString in recordedDates {
            let key = storageKeyPrefix + dateString
            if let data = defaults.data(forKey: key) {
                let fileURL = recordFileURL(for: dateString)
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    try? data.write(to: fileURL, options: .atomic)
                }
                keysToRemove.append(key)
            }
        }
        
        // 清理 UserDefaults 中其他遗留日期键
        for (key, _) in defaults.dictionaryRepresentation() where key.hasPrefix(storageKeyPrefix + "20") {
            let dateString = String(key.dropFirst(storageKeyPrefix.count))
            if let data = defaults.data(forKey: key) {
                let fileURL = recordFileURL(for: dateString)
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    try? data.write(to: fileURL, options: .atomic)
                }
            }
            keysToRemove.append(key)
        }
        
        for key in Set(keysToRemove) {
            defaults.removeObject(forKey: key)
        }
        if !recordedDates.isEmpty {
            defaults.removeObject(forKey: recordedDatesKey)
        }
    }
    
    private func loadRecord(for dateString: String) -> DailyScreenTimeRecord? {
        let fileURL = recordFileURL(for: dateString)
        if let data = try? Data(contentsOf: fileURL),
           let record = try? JSONDecoder().decode(DailyScreenTimeRecord.self, from: data) {
            return record
        }
        // 兜底兼容：若文件不存在，检查 UserDefaults（如测试注入的旧键）
        let key = storageKeyPrefix + dateString
        guard let data = UserDefaults.standard.data(forKey: key),
              let record = try? JSONDecoder().decode(DailyScreenTimeRecord.self, from: data) else {
            return nil
        }
        return record
    }
    
    private func aggregate(
        records: [DailyScreenTimeRecord],
        scope: TimeScope,
        periodDescription: String,
        buckets: [ScreenTimeBucket] = []
    ) -> AggregatedScreenTimeStats {
        var totalSec: TimeInterval = 0
        var totalIdleSec: TimeInterval = 0
        var mergedApps: [String: AppUsageRecord] = [:]
        var mergedEvents: [UUID: EventTriggerRecord] = [:]
        var allPastLogs: [PastEventLogItem] = []
        
        for r in records {
            totalSec += r.totalActiveSeconds
            totalIdleSec += r.totalIdleSeconds
            if let logs = r.pastEventLogs {
                allPastLogs.append(contentsOf: logs)
            }
            for (bundleId, app) in r.appUsages {
                if var exist = mergedApps[bundleId] {
                    exist.durationSeconds += app.durationSeconds
                    exist.activationCount += app.activationCount
                    if app.lastActiveDate > exist.lastActiveDate {
                        exist.lastActiveDate = app.lastActiveDate
                    }
                    mergedApps[bundleId] = exist
                } else {
                    mergedApps[bundleId] = app
                }
            }
            for (id, ev) in r.eventTriggers {
                if var exist = mergedEvents[id] {
                    exist.count += ev.count
                    let mergedIgnored = exist.effectiveIgnoredCount + ev.effectiveIgnoredCount
                    exist.ignoredCount = mergedIgnored > 0 ? mergedIgnored : nil
                    if ev.lastTriggeredAt > exist.lastTriggeredAt {
                        exist.lastTriggeredAt = ev.lastTriggeredAt
                    }
                    mergedEvents[id] = exist
                } else {
                    mergedEvents[id] = ev
                }
            }
        }
        
        allPastLogs.sort { $0.timestamp < $1.timestamp }
        let daysCount = max(1, records.count)
        let dailyAvg = totalSec / Double(daysCount)
        let sortedApps = mergedApps.values.sorted {
            if $0.durationSeconds != $1.durationSeconds {
                return $0.durationSeconds > $1.durationSeconds
            }
            return $0.bundleIdentifier < $1.bundleIdentifier
        }
        let sortedEvents = mergedEvents.values.sorted {
            if $0.count != $1.count {
                return $0.count > $1.count
            }
            if $0.lastTriggeredAt != $1.lastTriggeredAt {
                return $0.lastTriggeredAt > $1.lastTriggeredAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        let totalEventCount = mergedEvents.values.reduce(0) { $0 + $1.count }
        
        return AggregatedScreenTimeStats(
            scope: scope,
            totalActiveSeconds: totalSec,
            totalIdleSeconds: totalIdleSec,
            sortedApps: sortedApps,
            sortedEventTriggers: sortedEvents,
            totalEventTriggerCount: totalEventCount,
            periodDescription: periodDescription,
            dailyAverageSeconds: dailyAvg,
            pastEventLogs: allPastLogs,
            buckets: buckets
        )
    }
    
    // MARK: - 跨天处理与持久化
    private func checkDateRollOver() {
        let currentTodayStr = Self.dateFormatter.string(from: Date())
        if todayRecord.dateString != currentTodayStr {
            saveTodayRecord(force: true)
            todayRecord = DailyScreenTimeRecord(dateString: currentTodayStr)
            todayTotalSeconds = 0
            todayIdleSeconds = 0
            todaySortedApps = []
            todaySortedEventTriggers = []
            todayTotalEventTriggerCount = 0
            saveTodayRecord(force: true)
            refreshStats()
        }
    }
    
    private func saveTodayRecord(force: Bool = false) {
        lastSaveDate = Date()
        let fileURL = recordFileURL(for: todayRecord.dateString)
        if let data = try? JSONEncoder().encode(todayRecord) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
    
    private func loadTodayRecord() {
        let todayStr = Self.dateFormatter.string(from: Date())
        if let record = loadRecord(for: todayStr) {
            self.todayRecord = record
        } else {
            self.todayRecord = DailyScreenTimeRecord(dateString: todayStr)
        }
        self.todayTotalSeconds = todayRecord.totalActiveSeconds
        self.todayIdleSeconds = todayRecord.totalIdleSeconds
        self.todaySortedApps = todayRecord.sortedApps
        self.todaySortedEventTriggers = todayRecord.sortedEventTriggers
        self.todayTotalEventTriggerCount = todayRecord.totalEventTriggerCount
    }
    
    public func clearTodayData() {
        let todayStr = Self.dateFormatter.string(from: Date())
        todayRecord = DailyScreenTimeRecord(dateString: todayStr)
        todayTotalSeconds = 0
        todayIdleSeconds = 0
        todaySortedApps = []
        todaySortedEventTriggers = []
        todayTotalEventTriggerCount = 0
        saveTodayRecord(force: true)
        refreshStats()
    }
    
    /// 清除当前锚点日期的统计数据
    public func clearCurrentDateData() {
        if Calendar.current.isDateInToday(anchorDate) {
            clearTodayData()
        } else {
            let dateStr = Self.dateFormatter.string(from: anchorDate)
            try? FileManager.default.removeItem(at: recordFileURL(for: dateStr))
            UserDefaults.standard.removeObject(forKey: storageKeyPrefix + dateStr)
            refreshStats()
        }
    }
    
    public func icon(for bundleId: String) -> NSImage {
        if let cached = iconCache[bundleId] {
            return cached
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 32, height: 32)
            iconCache[bundleId] = icon
            return icon
        }
        let fallback = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        iconCache[bundleId] = fallback
        return fallback
    }
    
    public func recordAppUsageForTesting(bundleId: String, appName: String, duration: TimeInterval, activations: Int = 1) {
        currentForegroundApp = (name: appName, bundleId: bundleId)
        todayRecord.totalActiveSeconds += duration
        var record = todayRecord.appUsages[bundleId] ?? AppUsageRecord(
            bundleIdentifier: bundleId,
            appName: appName,
            durationSeconds: 0,
            activationCount: 0,
            lastActiveDate: Date()
        )
        record.durationSeconds += duration
        record.activationCount += activations
        todayRecord.appUsages[bundleId] = record
        todayTotalSeconds = todayRecord.totalActiveSeconds
        todaySortedApps = todayRecord.sortedApps
        refreshStats()
    }
}
