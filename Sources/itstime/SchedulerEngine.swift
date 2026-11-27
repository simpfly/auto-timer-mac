import Foundation
import AppKit
import SwiftUI
import Combine
import UserNotifications

@MainActor
public final class SchedulerEngine: ObservableObject {
    public static let shared = SchedulerEngine()
    
    private let tasksStorageKey = "ItsTime_Tasks_Storage_Key"
    private let legacyTasksStorageKey = "AutoTimerMac_Tasks_Storage_Key"
    
    @Published public var tasks: [ScheduleTask] = [] {
        didSet {
            saveTasks()
        }
    }
    
    /// 当前正在运行的最优先倒计时文本（供菜单栏常驻展示，如 "14:20"）
    @Published public private(set) var activeCountdownSummary: String? = nil
    
    /// 当前正在执行的音频播放提前 3 秒预告
    @Published public private(set) var pendingAudioAlert: (task: ScheduleTask, seconds: Int)? = nil
    
    /// 当前在菜单栏窗口内弹出的文本提示
    @Published public var activeTextAlert: TextAlertItem? = nil
    
    private var ticker: AnyCancellable?
    private var lastTickDate: Date = Date()
    private var isSystemSleeping: Bool = false
    private var isScreenAsleep: Bool = false
    private var isScreenLocked: Bool = false
    private var wasDndActive: Bool = false
    private var sleepObserver: Any?
    private var wakeObserver: Any?
    private var screenSleepObserver: Any?
    private var screenWakeObserver: Any?
    private var screenLockObserver: Any?
    private var screenUnlockObserver: Any?
    
    public init() {
        reloadTasks()
        startTimer()
        setupSleepWakeObservers()
        requestNotificationPermission()
    }
    
    deinit {
        let wsCenter = NSWorkspace.shared.notificationCenter
        if let o = sleepObserver { wsCenter.removeObserver(o) }
        if let o = wakeObserver { wsCenter.removeObserver(o) }
        if let o = screenSleepObserver { wsCenter.removeObserver(o) }
        if let o = screenWakeObserver { wsCenter.removeObserver(o) }
        let distCenter = DistributedNotificationCenter.default()
        if let o = screenLockObserver { distCenter.removeObserver(o) }
        if let o = screenUnlockObserver { distCenter.removeObserver(o) }
    }
    
    private func setupSleepWakeObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        
        // 1. 系统休眠与唤醒
        sleepObserver = wsCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleSystemWillSleep()
            }
        }
        
        wakeObserver = wsCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleSystemDidWake()
            }
        }
        
        // 2. 屏幕息屏与亮屏（息屏时绝不发声、绝不弹窗、绝不触发任务）
        screenSleepObserver = wsCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleScreenDidSleep()
            }
        }
        
        screenWakeObserver = wsCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleScreenDidWake()
            }
        }
        
        // 3. 锁屏与解锁
        let distCenter = DistributedNotificationCenter.default()
        screenLockObserver = distCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleScreenLocked()
            }
        }
        
        screenUnlockObserver = distCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleScreenUnlocked()
            }
        }
    }
    
    private func handleSystemWillSleep() {
        isSystemSleeping = true
        // 用户合盖或系统休眠时：若正在播放音频立即停止，并销毁气泡 HUD，杜绝合盖后发声
        AudioService.shared.stop(fadeOut: false)
        AudioPreAlertHUD.shared.dismiss()
        pendingAudioAlert = nil
    }
    
    private func handleSystemDidWake() {
        isSystemSleeping = false
        lastTickDate = Date()
        // 唤醒开盖时：清理休眠期间错过的提示与音频，绝不补发、不补播！
        cleanMissedTasksAfterWake()
    }
    
    private func handleScreenDidSleep() {
        isScreenAsleep = true
        AudioService.shared.stop(fadeOut: false)
        AudioPreAlertHUD.shared.dismiss()
        pendingAudioAlert = nil
    }
    
    private func handleScreenDidWake() {
        isScreenAsleep = false
        lastTickDate = Date()
        // 亮屏时清理息屏期间错过的任务（刷新周期，绝不触发、不补播）
        cleanMissedTasksAfterWake()
    }
    
    private func handleScreenLocked() {
        isScreenLocked = true
        AudioService.shared.stop(fadeOut: false)
        AudioPreAlertHUD.shared.dismiss()
        pendingAudioAlert = nil
        // 锁屏时立即刷新所有 interval/countdown 周期起点，
        // 防止解锁后因锁屏期间时间累积而立即触发
        cleanMissedTasksAfterWake()
    }
    
    private func handleScreenUnlocked() {
        isScreenLocked = false
        lastTickDate = Date()
        cleanMissedTasksAfterWake()
    }
    
    /// 清理合盖休眠期间错过的任务（刷新周期，不补播音频与通知）
    func cleanMissedTasksAfterWake() {
        AudioPreAlertHUD.shared.dismiss()
        self.pendingAudioAlert = nil
        let now = Date()
        let calendar = Calendar.current
        var changed = false
        
        for index in tasks.indices {
            guard tasks[index].isEnabled && !tasks[index].isPaused else { continue }
            
            switch tasks[index].trigger {
            case .once(let date):
                if date < now {
                    // 单次任务若在合盖期间过期，直接标记完成停用，不补发
                    tasks[index].isEnabled = false
                    tasks[index].lastTriggeredAt = now
                    changed = true
                }
            case .countdown(let totalSeconds):
                // 倒计时任务若在合盖期间结束，重置为初始时长，不补发
                if let rem = tasks[index].countdownRemainingSeconds, rem <= 0 {
                    tasks[index].countdownRemainingSeconds = totalSeconds
                    changed = true
                }
            case .daily(let hour, let minute):
                var comps = calendar.dateComponents([.year, .month, .day], from: now)
                comps.hour = hour
                comps.minute = minute
                comps.second = 0
                if let targetDate = calendar.date(from: comps) {
                    // 若今天的目标时刻已过（超出正常 15 秒容错），标记为今天已过，直接等待明天，不补播
                    if targetDate < now.addingTimeInterval(-15) {
                        tasks[index].lastTriggeredAt = now
                        changed = true
                    }
                }
            case .interval(let intervalSeconds):
                let last = tasks[index].lastTriggeredAt ?? tasks[index].createdAt
                let elapsed = now.timeIntervalSince(last)
                // 循环任务若在合盖期间到期，将起始时间重置为当前，从现在开始新的一轮循环，不补播
                if elapsed >= Double(intervalSeconds) {
                    tasks[index].lastTriggeredAt = now
                    changed = true
                }
            }
        }
        
        if changed {
            saveTasks()
        }
    }
    
    private var canUseNotificationCenter: Bool {
        guard NSClassFromString("XCTestCase") == nil,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              let id = Bundle.main.bundleIdentifier,
              !id.contains("xctest") else {
            return false
        }
        return true
    }
    
    private func requestNotificationPermission() {
        guard canUseNotificationCenter else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted {
                print("✅ 系统通知授权成功")
            }
        }
    }
    
    func reloadTasks() {
        var loaded: [ScheduleTask] = []
        let taskData = UserDefaults.standard.data(forKey: tasksStorageKey) ?? UserDefaults.standard.data(forKey: legacyTasksStorageKey)
        if let data = taskData,
           let decoded = try? JSONDecoder().decode([ScheduleTask].self, from: data) {
            loaded = decoded
        }
        
        let hasEyeTask = loaded.contains { $0.name.contains("眼保健操") || $0.name.contains("护眼") }
        let hasWaterTask = loaded.contains { $0.name.contains("喝杯水") || $0.name.contains("饮水") }
        let hasBaduanjinTask = loaded.contains { $0.name.contains("八段锦") }
        
        if loaded.isEmpty {
            loaded = [
                ScheduleTask(
                    name: "做眼保健操",
                    trigger: .interval(intervalSeconds: 45 * 60),
                    action: .playLocalAudio(
                        filePath: "Resources/Audio/眼保健操.mp3",
                        displayName: "眼保健操",
                        loop: false,
                        volume: 0.8,
                        durationSeconds: nil
                    ),
                    isEnabled: true
                ),
                ScheduleTask(
                    name: "喝杯水",
                    trigger: .interval(intervalSeconds: 30 * 60),
                    action: .popupContent(mode: .textNotification(message: "喝杯水")),
                    isEnabled: true
                ),
                ScheduleTask(
                    name: "八段锦",
                    trigger: .daily(hour: 16, minute: 0),
                    action: .playLocalAudio(
                        filePath: "Resources/Audio/健身气功八段锦口令.mp3",
                        displayName: "健身气功八段锦口令",
                        loop: false,
                        volume: 0.8,
                        durationSeconds: nil
                    ),
                    isEnabled: true
                )
            ]
        } else {
            // 已有旧数据时，智能补充预设任务
            if !hasEyeTask {
                loaded.append(ScheduleTask(
                    name: "做眼保健操",
                    trigger: .interval(intervalSeconds: 45 * 60),
                    action: .playLocalAudio(
                        filePath: "Resources/Audio/眼保健操.mp3",
                        displayName: "眼保健操",
                        loop: false,
                        volume: 0.8,
                        durationSeconds: nil
                    ),
                    isEnabled: true
                ))
            }
            if !hasWaterTask {
                loaded.append(ScheduleTask(
                    name: "喝杯水",
                    trigger: .interval(intervalSeconds: 30 * 60),
                    action: .popupContent(mode: .textNotification(message: "喝杯水")),
                    isEnabled: true
                ))
            }
            if !hasBaduanjinTask {
                loaded.append(ScheduleTask(
                    name: "八段锦",
                    trigger: .daily(hour: 16, minute: 0),
                    action: .playLocalAudio(
                        filePath: "Resources/Audio/健身气功八段锦口令.mp3",
                        displayName: "健身气功八段锦口令",
                        loop: false,
                        volume: 0.8,
                        durationSeconds: nil
                    ),
                    isEnabled: true
                ))
            }
        }
        
        // 自动清理早会与预设番茄钟
        loaded.removeAll { task in
            let name = task.name
            if name.contains("早会") { return true }
            if name == "倒计时" || name == "深度专注番茄钟" || name == "番茄钟" { return true }
            return false
        }
        
        // 平滑迁移旧数据中的任务名称与清理不可编辑的副文本
        for i in 0..<loaded.count {
            if loaded[i].name == "做眼保健操" || loaded[i].name == "眼保健操与活动" || loaded[i].name == "护眼" {
                loaded[i].name = "做眼保健操"
                if case .interval(let sec) = loaded[i].trigger, sec == 30 * 60 {
                    loaded[i].trigger = .interval(intervalSeconds: 45 * 60)
                }
            }
            if loaded[i].name == "站立与饮水提醒" {
                loaded[i].name = "喝杯水"
            }
            if loaded[i].name == "工间八段锦" {
                loaded[i].name = "八段锦"
            }
            // 清除写死的、不可编辑的文本提醒副文本
            if case .popupContent(let mode) = loaded[i].action {
                if case .textNotification = mode {
                    loaded[i].action = .popupContent(mode: .textNotification(message: loaded[i].name))
                }
            }
        }
        
        self.tasks = loaded
    }
    
    private func saveTasks() {
        if let encoded = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(encoded, forKey: tasksStorageKey)
        }
    }
    
    private func startTimer() {
        ticker = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.onTick()
            }
    }
    
    /// 实时查询系统原生显示器息屏与锁屏会话状态（结合 CoreGraphics 硬件显示状态、系统会话字典与通知）
    public var isScreenOrSessionLocked: Bool {
        if isScreenAsleep || isScreenLocked || isSystemSleeping {
            return true
        }
        // 1. 查询系统主显示器是否处于物理息屏状态
        if CGDisplayIsAsleep(CGMainDisplayID()) != 0 {
            return true
        }
        // 2. 查询 macOS 当前登录会话字典是否标记为锁屏
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any],
           let locked = session["CGSSessionScreenIsLocked"] as? Bool, locked {
            return true
        }
        return false
    }
    
    func onTick() {
        guard !isScreenOrSessionLocked else {
            lastTickDate = Date()
            return
        }
        
        // 临时免打扰期间：暂停所有触发与预告，到期后自动恢复并刷新周期（不补发）
        if AppPreferences.shared.isDndActive {
            wasDndActive = true
            if pendingAudioAlert != nil {
                AudioPreAlertHUD.shared.dismiss()
                pendingAudioAlert = nil
            }
            activeCountdownSummary = nil
            lastTickDate = Date()
            return
        } else if wasDndActive {
            wasDndActive = false
            AppPreferences.shared.clearDnd()
            lastTickDate = Date()
            cleanMissedTasksAfterWake()
            return
        }
        
        let now = Date()
        let timeGap = now.timeIntervalSince(lastTickDate)
        lastTickDate = now
        
        // 若时钟跳跃超过 5 秒（合盖休眠唤醒），清理错过的任务，跳过本轮执行，绝不补播音频
        if timeGap > 5.0 {
            cleanMissedTasksAfterWake()
            return
        }
        
        var justTriggeredTaskId: UUID? = nil
        // 1. 推进当前正在进行的音频预告倒计时（保证足额 5s -> 4s -> 3s -> 2s -> 1s，绝不提前播放音频）
        if var alert = self.pendingAudioAlert {
            alert.seconds -= 1
            if alert.seconds <= 0 {
                // 5s 完整倒数完毕，在第 5 秒末自然归零，触发播放！
                AudioPreAlertHUD.shared.dismiss()
                self.pendingAudioAlert = nil
                justTriggeredTaskId = alert.task.id
                
                let task = alert.task
                if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
                    var triggeredTask = tasks[idx]
                    triggeredTask.lastTriggeredAt = now
                    if case .once = triggeredTask.trigger {
                        triggeredTask.isEnabled = false
                    } else if case .countdown(let totalSeconds) = triggeredTask.trigger {
                        triggeredTask.countdownRemainingSeconds = totalSeconds
                    }
                    tasks[idx] = triggeredTask
                    saveTasks()
                    executeAction(for: triggeredTask)
                } else {
                    executeAction(for: task)
                }
            } else {
                // 更新预告 HUD 倒数秒数
                self.pendingAudioAlert = alert
                var audioName = ""
                if case .playLocalAudio(_, let name, _, _, _) = alert.task.action {
                    audioName = name
                }
                AudioPreAlertHUD.shared.update(
                    alert: AudioPreAlertInfo(
                        taskId: alert.task.id,
                        taskName: alert.task.name,
                        audioName: audioName,
                        secondsRemaining: alert.seconds
                    )
                )
            }
        }
        
        let calendar = Calendar.current
        let preAlertSeconds = max(0, AppPreferences.shared.audioPreAlertSeconds)
        var firstActiveCountdown: (title: String, remaining: Int)? = nil
        var candidatePreAudioAlert: ScheduleTask? = nil
        
        for index in tasks.indices {
            guard tasks[index].isEnabled && !tasks[index].isPaused else { continue }
            
            // 刚在本轮预告完成触发的任务，跳过当轮后续检查，等待下一个周期
            if tasks[index].id == justTriggeredTaskId {
                continue
            }
            
            // 若当前任务已被预告状态机接管，其触发与倒数全权交由预告状态机，避免普通分支提前触发
            if let activeAlert = self.pendingAudioAlert, activeAlert.task.id == tasks[index].id {
                if case .countdown = tasks[index].trigger {
                    tasks[index].countdownRemainingSeconds = activeAlert.seconds
                    if firstActiveCountdown == nil {
                        firstActiveCountdown = (tasks[index].name, activeAlert.seconds)
                    }
                }
                continue
            }
            
            let isAudioAction: Bool = {
                if case .playLocalAudio = tasks[index].action { return true }
                return false
            }()
            let usePreAlert = isAudioAction && preAlertSeconds > 0
            
            switch tasks[index].trigger {
            case .once(let date):
                let diff = date.timeIntervalSince(now)
                if usePreAlert {
                    if diff <= Double(preAlertSeconds) && diff >= -30 {
                        if candidatePreAudioAlert == nil && self.pendingAudioAlert == nil {
                            candidatePreAudioAlert = tasks[index]
                        }
                    } else if diff < -30 {
                        // 严重超期（如合盖/重启错过）→ 静默禁用，不再卡循环
                        tasks[index].isEnabled = false
                        tasks[index].lastTriggeredAt = now
                        saveTasks()
                    }
                } else {
                    // 非音频任务或关闭预告：常规即时触发
                    if diff <= 0 {
                        var finished = tasks[index]
                        finished.lastTriggeredAt = now
                        finished.isEnabled = false
                        tasks[index] = finished
                        saveTasks()
                        if diff >= -30 {
                            executeAction(for: finished)
                        }
                    }
                }
                
            case .countdown(let totalSeconds):
                var remaining = tasks[index].countdownRemainingSeconds ?? totalSeconds
                remaining -= 1
                if remaining < 0 { remaining = 0 }
                tasks[index].countdownRemainingSeconds = remaining
                
                if firstActiveCountdown == nil {
                    firstActiveCountdown = (tasks[index].name, remaining)
                }
                
                if usePreAlert {
                    if remaining <= preAlertSeconds {
                        if candidatePreAudioAlert == nil && self.pendingAudioAlert == nil {
                            candidatePreAudioAlert = tasks[index]
                        }
                    }
                } else {
                    // 归零即触发
                    if remaining <= 0 {
                        tasks[index].countdownRemainingSeconds = totalSeconds
                        tasks[index].lastTriggeredAt = now
                        saveTasks()
                        executeAction(for: tasks[index])
                    }
                }
                
            case .daily(let hour, let minute):
                var targetComps = calendar.dateComponents([.year, .month, .day], from: now)
                targetComps.hour = hour
                targetComps.minute = minute
                targetComps.second = 0
                guard let targetDate = calendar.date(from: targetComps) else { break }
                
                let diff = targetDate.timeIntervalSince(now) // >0 未到达, <=0 已过
                let lastTriggered = tasks[index].lastTriggeredAt
                let alreadyTriggeredToday = lastTriggered.map {
                    calendar.isDate($0, inSameDayAs: now) && abs($0.timeIntervalSince(targetDate)) < 120
                } ?? false
                
                if !alreadyTriggeredToday {
                    if usePreAlert {
                        if diff <= Double(preAlertSeconds) && diff >= -15 {
                            if candidatePreAudioAlert == nil && self.pendingAudioAlert == nil {
                                candidatePreAudioAlert = tasks[index]
                            }
                        } else if diff < -15 {
                            // 超期超出容错窗口 → 静默标记为今日已触发，防止死循环
                            tasks[index].lastTriggeredAt = now
                            saveTasks()
                        }
                    } else {
                        if diff <= 0 && diff >= -15 {
                            tasks[index].lastTriggeredAt = now
                            saveTasks()
                            executeAction(for: tasks[index])
                        }
                    }
                }
                
            case .interval(let intervalSeconds):
                let last = tasks[index].lastTriggeredAt ?? tasks[index].createdAt
                let elapsed = now.timeIntervalSince(last)
                let remaining = Double(intervalSeconds) - elapsed
                
                if usePreAlert {
                    if remaining <= Double(preAlertSeconds) && remaining >= -30 {
                        if candidatePreAudioAlert == nil && self.pendingAudioAlert == nil {
                            candidatePreAudioAlert = tasks[index]
                        }
                    } else if remaining < -30 {
                        // 严重超期（合盖/重启错过 > 30s）→ 静默刷新为当前时间，开启新周期，绝不死锁
                        tasks[index].lastTriggeredAt = now
                        saveTasks()
                    }
                } else {
                    if remaining <= 0 {
                        tasks[index].lastTriggeredAt = now
                        saveTasks()
                        if remaining >= -30 {
                            executeAction(for: tasks[index])
                        }
                    }
                }
            }
        }
        
        // 若产生了新的音频预告候选任务，且当前无预告进行中，立即启动 5 秒完整预告卡片
        if let candidate = candidatePreAudioAlert, self.pendingAudioAlert == nil {
            startAudioPreAlert(for: candidate)
        }
        
        // 菜单栏常驻摘要（预告优先显示声波倒数，其次为倒计时任务）
        if let preAlert = self.pendingAudioAlert {
            self.activeCountdownSummary = "\(preAlert.seconds)s"
        } else if let active = firstActiveCountdown {
            let m = active.remaining / 60
            let s = active.remaining % 60
            self.activeCountdownSummary = String(format: "%02d:%02d", m, s)
        } else {
            self.activeCountdownSummary = nil
        }
    }
    
    /// 启动音频任务倒计时预告卡片（根据偏好设置决定预告秒数）
    public func startAudioPreAlert(for task: ScheduleTask) {
        let seconds = max(1, AppPreferences.shared.audioPreAlertSeconds)
        // 若处于全屏或会议避让中，跳过预告卡片并直接进入避让处理
        if AppPreferences.shared.avoidanceEnabled && InterruptionGuard.shouldAvoidNow() {
            if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[idx].lastTriggeredAt = Date()
                if case .once = tasks[idx].trigger {
                    tasks[idx].isEnabled = false
                } else if case .countdown(let total) = tasks[idx].trigger {
                    tasks[idx].countdownRemainingSeconds = total
                }
                saveTasks()
            }
            if AppPreferences.shared.avoidanceBehavior == .silentNotification {
                notify(title: "定时提醒（已避让）", body: "「\(task.name)」时间已到", withSystemSound: false)
            }
            return
        }
        
        self.pendingAudioAlert = (task: task, seconds: seconds)
        var audioName = ""
        if case .playLocalAudio(_, let name, _, _, _) = task.action {
            audioName = name
        }
        AudioPreAlertHUD.shared.update(
            alert: AudioPreAlertInfo(
                taskId: task.id,
                taskName: task.name,
                audioName: audioName,
                secondsRemaining: seconds
            )
        )
    }
    
    /// 用户在预告卡片点击【立即播放】
    public func playAudioImmediatelyFromPreAlert() {
        guard let alert = self.pendingAudioAlert else { return }
        AudioPreAlertHUD.shared.dismiss()
        self.pendingAudioAlert = nil
        let task = alert.task
        let now = Date()
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            var triggeredTask = tasks[idx]
            triggeredTask.lastTriggeredAt = now
            if case .once = triggeredTask.trigger {
                triggeredTask.isEnabled = false
            } else if case .countdown(let totalSeconds) = triggeredTask.trigger {
                triggeredTask.countdownRemainingSeconds = totalSeconds
            }
            tasks[idx] = triggeredTask
            saveTasks()
            executeAction(for: triggeredTask)
        } else {
            executeAction(for: task)
        }
    }
    
    /// 用户在气泡点击“跳过本次”
    public func skipAudioPreAlert() {
        guard let alert = self.pendingAudioAlert else { return }
        if let idx = tasks.firstIndex(where: { $0.id == alert.task.id }) {
            let now = Date()
            tasks[idx].lastTriggeredAt = now
            if case .countdown(let total) = tasks[idx].trigger {
                tasks[idx].countdownRemainingSeconds = total
            } else if case .once = tasks[idx].trigger {
                tasks[idx].isEnabled = false
            }
            saveTasks()
        }
        AudioPreAlertHUD.shared.dismiss()
        self.pendingAudioAlert = nil
    }
    
    /// 执行动作（手动测试运行时不计入正式触发统计）
    public func executeAction(for task: ScheduleTask, isManualTest: Bool = false) {
        // 全屏或会议场景自动避让（仅针对自动调度触发，手动测试不受影响）
        if !isManualTest && AppPreferences.shared.avoidanceEnabled && InterruptionGuard.shouldAvoidNow() {
            if AppPreferences.shared.avoidanceBehavior == .silentNotification {
                notify(
                    title: "定时提醒（已避让）",
                    body: "「\(task.name)」时间已到",
                    withSystemSound: false
                )
            }
            return
        }
        
        // 1. 仅正式调度触发时计入统计与历史时间轴
        if !isManualTest {
            if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[idx].triggerCount = tasks[idx].effectiveTriggerCount + 1
                saveTasks()
            }
            ScreenTimeTrackerService.shared.recordEventTrigger(for: task)
        }
        
        // 2. 执行具体动作
        switch task.action {
        case .none:
            AudioService.shared.playNotificationChime()
            notify(
                title: "声音通知",
                body: "「\(task.name)」时间已到！",
                withSystemSound: true
            )
            
        case .popupContent(let mode):
            AudioService.shared.playNotificationChime()
            if case .textNotification(let msg) = mode {
                let alertMsg = msg.isEmpty ? task.name : msg
                // 根据任务触发类型获取专属高亮颜色
                let taskColor: Color
                switch task.trigger {
                case .countdown, .once:
                    taskColor = .orange
                case .daily:
                    taskColor = .indigo
                case .interval:
                    taskColor = .teal
                }
                // 纯文本提醒：在菜单栏图标下方弹出专属提醒卡片，等待用户确认
                TextAlertHUD.shared.show(title: task.name, message: alertMsg, color: taskColor)
            } else {
                PopupHUDManager.shared.show(for: task, mode: mode)
            }
            let notifyTitle: String
            let notifyBody: String
            if case .textNotification = mode {
                notifyTitle = "文本提醒"
                notifyBody = "「\(task.name)」"
            } else {
                notifyTitle = "定时提醒"
                notifyBody = "「\(task.name)」时间已到"
            }
            notify(
                title: notifyTitle,
                body: notifyBody,
                withSystemSound: true
            )
            
        case .playLocalAudio(let path, let name, let loop, let volume, let duration):
            let success = AudioService.shared.playLocalFile(
                atPath: path,
                displayName: name,
                loop: loop,
                volume: volume,
                durationSeconds: duration,
                fadeIn: true
            )
            let actualName = name.isEmpty ? (path as NSString).lastPathComponent : name
            if !success {
                AudioService.shared.playNotificationChime()
            }
            notify(
                title: success ? "定时音频正在播放" : "定时提醒 (音频文件已丢失)",
                body: "「\(task.name)」\(success ? "触发播放: \(actualName)" : "音频文件不存在或已移动，已为您降级为铃声提醒")",
                withSystemSound: !success
            )
            
        case .openURL(let urlString):
            AudioService.shared.playNotificationChime()
            let (_, sanitized) = ScheduleTask.sanitizeURLString(urlString)
            if let targetURL = URL(string: sanitized) {
                NSWorkspace.shared.open(targetURL)
                notify(
                    title: "定时链接自动打开",
                    body: "「\(task.name)」已为您打开: \(sanitized)",
                    withSystemSound: true
                )
            } else {
                print("❌ 无效链接: \(urlString)")
            }
        }
    }
    
    private func notify(title: String, body: String, withSystemSound: Bool = false) {
        guard canUseNotificationCenter else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if withSystemSound {
            content.sound = UNNotificationSound.default
        }
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("通知发送错误: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - 操作接口
    public func addTask(_ task: ScheduleTask) {
        tasks.append(task)
    }
    
    public func updateTask(_ task: ScheduleTask) {
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx] = task
            cleanupOrphanedAudioFiles()
        }
    }
    
    public func deleteTask(byId id: UUID) {
        tasks.removeAll { $0.id == id }
        cleanupOrphanedAudioFiles()
    }
    
    private func cleanupOrphanedAudioFiles() {
        let referencedPaths: [String] = tasks.compactMap { task in
            if case .playLocalAudio(let path, _, _, _, _) = task.action {
                return path
            }
            return nil
        }
        AudioService.cleanupOrphanedManagedAudio(referencedPaths: referencedPaths)
    }
    
    // MARK: - 临时免打扰快捷操作
    
    public func enableDndForOneHour() {
        AppPreferences.shared.enableDndForOneHour()
        AudioService.shared.stop(fadeOut: false)
        AudioPreAlertHUD.shared.dismiss()
        pendingAudioAlert = nil
    }
    
    public func enableDndUntilTomorrow() {
        AppPreferences.shared.enableDndUntilTomorrow()
        AudioService.shared.stop(fadeOut: false)
        AudioPreAlertHUD.shared.dismiss()
        pendingAudioAlert = nil
    }
    
    public func clearDnd() {
        AppPreferences.shared.clearDnd()
        lastTickDate = Date()
        cleanMissedTasksAfterWake()
    }
    
    public func toggleTaskEnabled(id: UUID) {
        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            if !tasks[idx].isEnabled, case .once(let date) = tasks[idx].trigger, date <= Date() {
                let time = Calendar.current.dateComponents([.hour, .minute], from: date)
                guard let next = Calendar.current.nextDate(after: Date(), matching: time, matchingPolicy: .nextTime) else { return }
                tasks[idx].trigger = .once(next)
            }
            tasks[idx].isEnabled.toggle()
            if tasks[idx].isEnabled {
                tasks[idx].isPaused = false
            }
            if case .countdown(let totalSeconds) = tasks[idx].trigger {
                tasks[idx].countdownRemainingSeconds = totalSeconds
            }
        }
    }
    
    public func toggleTaskPause(id: UUID) {
        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            tasks[idx].isPaused.toggle()
        }
    }
    
    public func resetCountdown(id: UUID) {
        if let idx = tasks.firstIndex(where: { $0.id == id }),
           case .countdown(let totalSeconds) = tasks[idx].trigger {
            tasks[idx].countdownRemainingSeconds = totalSeconds
            tasks[idx].isPaused = false
        }
    }
    
    /// 是否存在任何已启用且正在运行（未暂停）的任务
    public var hasActiveRunningTasks: Bool {
        return tasks.contains { $0.isEnabled && !$0.isPaused }
    }
    
    /// 一键暂停所有已启用任务，或恢复所有已启用任务
    public func togglePauseAll() {
        let shouldPause = hasActiveRunningTasks
        for idx in tasks.indices {
            if tasks[idx].isEnabled {
                tasks[idx].isPaused = shouldPause
            }
        }
    }
    
    /// 关闭菜单栏当前弹出的文本提示
    public func dismissTextAlert() {
        activeTextAlert = nil
    }
}

// MARK: - 菜单栏弹出的文本提示条目
public struct TextAlertItem: Identifiable, Equatable {
    public let id = UUID()
    public let title: String
    public let message: String
    public let date: Date
    
    public init(title: String, message: String, date: Date = Date()) {
        self.title = title
        self.message = message
        self.date = date
    }
}
