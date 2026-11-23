import Foundation
import AppKit
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
    private var sleepObserver: Any?
    private var wakeObserver: Any?
    
    public init() {
        loadTasks()
        startTimer()
        setupSleepWakeObservers()
        requestNotificationPermission()
    }
    
    private func setupSleepWakeObservers() {
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSystemWillSleep()
            }
        }
        
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSystemDidWake()
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
    
    /// 清理合盖休眠期间错过的任务（刷新周期，不补播音频与通知）
    private func cleanMissedTasksAfterWake() {
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
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted {
                print("✅ 系统通知授权成功")
            }
        }
    }
    
    private func loadTasks() {
        var loaded: [ScheduleTask] = []
        let taskData = UserDefaults.standard.data(forKey: tasksStorageKey) ?? UserDefaults.standard.data(forKey: legacyTasksStorageKey)
        if let data = taskData,
           let decoded = try? JSONDecoder().decode([ScheduleTask].self, from: data) {
            loaded = decoded
        }
        
        let hasEyeTask = loaded.contains { $0.name.contains("护眼") || $0.name.contains("眼保健操") }
        let hasBaduanjinTask = loaded.contains { $0.name.contains("八段锦") }
        
        if loaded.isEmpty {
            loaded = [
                ScheduleTask(
                    name: "护眼",
                    trigger: .interval(intervalSeconds: 30 * 60),
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
            // 已有旧数据时，智能补充预设音频任务
            if !hasEyeTask {
                loaded.append(ScheduleTask(
                    name: "护眼",
                    trigger: .interval(intervalSeconds: 30 * 60),
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
        
        // 平滑迁移旧数据中的任务名称（去“工间”，叫“八段锦”）
        for i in 0..<loaded.count {
            if loaded[i].name == "工间八段锦" {
                loaded[i].name = "八段锦"
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
    
    private func onTick() {
        guard !isSystemSleeping else { return }
        let now = Date()
        let timeGap = now.timeIntervalSince(lastTickDate)
        lastTickDate = now
        
        // 若时钟跳跃超过 5 秒（合盖休眠唤醒），清理错过的任务，跳过本轮执行，绝不补播音频
        if timeGap > 5.0 {
            cleanMissedTasksAfterWake()
            return
        }
        
        let calendar = Calendar.current
        var firstActiveCountdown: (title: String, remaining: Int)? = nil
        var detectedPreAudioAlert: (task: ScheduleTask, seconds: Int)? = nil
        
        for index in tasks.indices {
            guard tasks[index].isEnabled && !tasks[index].isPaused else { continue }
            
            let isAudioAction: Bool = {
                if case .playLocalAudio = tasks[index].action { return true }
                return false
            }()
            
            switch tasks[index].trigger {
            case .once(let date):
                let diff = date.timeIntervalSince(now)
                if diff <= 0 {
                    var finished = tasks[index]
                    finished.lastTriggeredAt = now
                    finished.isEnabled = false
                    tasks[index] = finished
                    saveTasks()
                    // 超期超过 30 秒（合盖休眠错过），不播放不提醒
                    if diff >= -30 {
                        executeAction(for: finished)
                    }
                } else if isAudioAction && diff > 0 && diff <= 3.5 {
                    let sec = max(1, Int(ceil(diff)))
                    if detectedPreAudioAlert == nil || sec < detectedPreAudioAlert!.seconds {
                        detectedPreAudioAlert = (tasks[index], sec)
                    }
                }
            case .countdown(let totalSeconds):
                var remaining = tasks[index].countdownRemainingSeconds ?? totalSeconds
                remaining -= 1
                if remaining <= 0 {
                    tasks[index].countdownRemainingSeconds = totalSeconds
                    tasks[index].lastTriggeredAt = now
                    saveTasks()
                    executeAction(for: tasks[index])
                } else {
                    tasks[index].countdownRemainingSeconds = remaining
                    if firstActiveCountdown == nil {
                        firstActiveCountdown = (tasks[index].name, remaining)
                    }
                    if isAudioAction && remaining >= 1 && remaining <= 3 {
                        if detectedPreAudioAlert == nil || remaining < detectedPreAudioAlert!.seconds {
                            detectedPreAudioAlert = (tasks[index], remaining)
                        }
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
                    if diff <= 0 && diff >= -15 {
                        // 在到达目标时刻后 15 秒容错窗口内触发，超时则不触发（防合盖补播）
                        tasks[index].lastTriggeredAt = now
                        saveTasks()
                        executeAction(for: tasks[index])
                    } else if isAudioAction && diff > 0 && diff <= 3.5 {
                        let sec = max(1, Int(ceil(diff)))
                        if detectedPreAudioAlert == nil || sec < detectedPreAudioAlert!.seconds {
                            detectedPreAudioAlert = (tasks[index], sec)
                        }
                    }
                }
                
            case .interval(let intervalSeconds):
                let last = tasks[index].lastTriggeredAt ?? tasks[index].createdAt
                let elapsed = now.timeIntervalSince(last)
                let remaining = Double(intervalSeconds) - elapsed
                
                if remaining <= 0 {
                    tasks[index].lastTriggeredAt = now
                    saveTasks()
                    // 若超期超过 30 秒（合盖休眠错过），不播放不提醒，静默进入下一轮
                    if remaining >= -30 {
                        executeAction(for: tasks[index])
                    }
                } else if isAudioAction && remaining > 0 && remaining <= 3.5 {
                    let sec = max(1, Int(ceil(remaining)))
                    if detectedPreAudioAlert == nil || sec < detectedPreAudioAlert!.seconds {
                        detectedPreAudioAlert = (tasks[index], sec)
                    }
                }
            }
        }
        
        // 处理音频播放提前 3 秒气泡预告
        if let alert = detectedPreAudioAlert {
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
        } else {
            if self.pendingAudioAlert != nil {
                AudioPreAlertHUD.shared.dismiss()
                self.pendingAudioAlert = nil
            }
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
    
    /// 用户在气泡点击“跳过本次”
    public func skipAudioPreAlert() {
        guard let alert = self.pendingAudioAlert else { return }
        if let idx = tasks.firstIndex(where: { $0.id == alert.task.id }) {
            let now = Date()
            tasks[idx].lastTriggeredAt = now
            if case .countdown(let total) = tasks[idx].trigger {
                tasks[idx].countdownRemainingSeconds = total
            }
        }
        AudioPreAlertHUD.shared.dismiss()
        self.pendingAudioAlert = nil
    }
    
    /// 执行动作
    public func executeAction(for task: ScheduleTask) {
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
                // 纯文本提醒：在菜单栏图标下方弹出专属提醒卡片，等待用户确认
                TextAlertHUD.shared.show(title: task.name, message: alertMsg)
            } else {
                PopupHUDManager.shared.show(for: task, mode: mode)
            }
            let notifyTitle: String
            let notifyBody: String
            if case .textNotification(let msg) = mode {
                notifyTitle = "文本提醒"
                notifyBody = "「\(msg.isEmpty ? task.name : msg)」"
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
        }
    }
    
    public func deleteTask(byId id: UUID) {
        tasks.removeAll { $0.id == id }
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
