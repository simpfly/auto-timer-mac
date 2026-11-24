import XCTest
@testable import itstime

@MainActor
final class SleepWakeGuardTests: XCTestCase {
    
    private var engine: SchedulerEngine!
    private var originalTasks: [ScheduleTask] = []
    
    override func setUp() async throws {
        try await super.setUp()
        engine = SchedulerEngine.shared
        originalTasks = engine.tasks
    }
    
    override func tearDown() async throws {
        engine.tasks = originalTasks
        try await super.tearDown()
    }
    
    // MARK: - 休眠唤醒测试：单次任务过期后直接停用，坚决不补发
    func testWakeCleanMissedOnceTask() {
        let expiredDate = Date().addingTimeInterval(-3600) // 1小时前已过期
        let expiredTask = ScheduleTask(
            name: "已过期的单次会议提醒",
            trigger: .once(expiredDate),
            isEnabled: true
        )
        engine.tasks = [expiredTask]
        
        // 模拟系统唤醒执行清理
        engine.cleanMissedTasksAfterWake()
        
        let cleaned = engine.tasks.first { $0.id == expiredTask.id }
        XCTAssertEqual(cleaned?.isEnabled, false, "合盖期间过期的单次任务应自动停用，杜绝唤醒时突兀补发")
        XCTAssertNotNil(cleaned?.lastTriggeredAt)
    }
    
    // MARK: - 休眠唤醒测试：倒计时任务若在休眠中归零，自动重置总时长，不补发
    func testWakeCleanMissedCountdownTask() {
        var countdownTask = ScheduleTask(
            name: "番茄专注",
            trigger: .countdown(totalSeconds: 1500),
            isEnabled: true
        )
        countdownTask.countdownRemainingSeconds = 0 // 已归零
        engine.tasks = [countdownTask]
        
        // 模拟唤醒清理
        engine.cleanMissedTasksAfterWake()
        
        let cleaned = engine.tasks.first { $0.id == countdownTask.id }
        XCTAssertEqual(cleaned?.countdownRemainingSeconds, 1500, "休眠期间结束的倒计时应恢复初始总时长")
    }
    
    // MARK: - 休眠唤醒测试：每日定时任务若已错过（超出 15 秒容错），静默等待次日
    func testWakeCleanMissedDailyTask() {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let now = Date()
        
        // 创建一个比当前时间早 30 分钟的“每日任务”
        let pastTime = now.addingTimeInterval(-1800)
        let pastComps = calendar.dateComponents([.hour, .minute], from: pastTime)
        
        let dailyTask = ScheduleTask(
            name: "已错过的每日提醒",
            trigger: .daily(hour: pastComps.hour ?? 9, minute: pastComps.minute ?? 0),
            isEnabled: true
        )
        engine.tasks = [dailyTask]
        
        engine.cleanMissedTasksAfterWake()
        
        let cleaned = engine.tasks.first { $0.id == dailyTask.id }
        XCTAssertNotNil(cleaned?.lastTriggeredAt, "错过的每日任务应标记最后触发时间为当前，避免开盖时突兀触发")
    }
    
    // MARK: - 休眠唤醒测试：循环间隔任务若在休眠中到期，重置为新一轮起点，不补播
    func testWakeCleanMissedIntervalTask() {
        let longAgo = Date().addingTimeInterval(-7200) // 2小时前触发
        var intervalTask = ScheduleTask(
            name: "护眼眼保健操",
            trigger: .interval(intervalSeconds: 1800), // 每30分钟
            isEnabled: true
        )
        intervalTask.lastTriggeredAt = longAgo
        engine.tasks = [intervalTask]
        
        engine.cleanMissedTasksAfterWake()
        
        let cleaned = engine.tasks.first { $0.id == intervalTask.id }
        guard let lastTrigger = cleaned?.lastTriggeredAt else {
            XCTFail("lastTriggeredAt 不应为空")
            return
        }
        // 验证 lastTriggeredAt 被更新为接近 now 的时刻
        XCTAssertTrue(abs(lastTrigger.timeIntervalSinceNow) < 5.0, "应以唤醒当前时间开启全新周期，避免补播长音频")
    }
    
    // MARK: - 音频预告“跳过本次”接口体验测试
    func testSkipAudioPreAlert() {
        let audioTask = ScheduleTask(
            name: "八段锦预告",
            trigger: .countdown(totalSeconds: 300),
            action: .playLocalAudio(
                filePath: "Resources/Audio/健身气功八段锦口令.mp3",
                displayName: "八段锦",
                loop: false,
                volume: 0.8,
                durationSeconds: nil
            ),
            isEnabled: true
        )
        engine.tasks = [audioTask]
        
        // 模拟提前 5 秒检测到了预告卡片
        engine.startAudioPreAlert(for: audioTask)
        XCTAssertEqual(engine.pendingAudioAlert?.seconds, 5)
        
        // 验证用户在卡片上点击“不播放/跳过本次”
        engine.skipAudioPreAlert()
        XCTAssertNil(engine.pendingAudioAlert)
    }
    
    // MARK: - 音频预告卡片支持用户点击【立即播放】
    func testPlayAudioImmediatelyFromPreAlert() {
        let audioTask = ScheduleTask(
            name: "立即播放测试",
            trigger: .countdown(totalSeconds: 300),
            action: .playLocalAudio(
                filePath: "Resources/Audio/健身气功八段锦口令.mp3",
                displayName: "八段锦",
                loop: false,
                volume: 0.8,
                durationSeconds: nil
            ),
            isEnabled: true
        )
        engine.tasks = [audioTask]
        engine.startAudioPreAlert(for: audioTask)
        XCTAssertNotNil(engine.pendingAudioAlert)
        
        // 点击立即播放
        engine.playAudioImmediatelyFromPreAlert()
        XCTAssertNil(engine.pendingAudioAlert, "点击立即播放后预告卡片应关闭")
        XCTAssertEqual(engine.tasks.first?.effectiveTriggerCount, 1, "应立即触发播放动作")
    }
    
    // MARK: - 音频预告状态机足额 5 秒倒计时测试（杜绝提前播放）
    func testAudioPreAlertFullFiveSecondsCountdown() {
        var audioTask = ScheduleTask(
            name: "足额预告倒计时测试",
            trigger: .countdown(totalSeconds: 7),
            action: .playLocalAudio(
                filePath: "Resources/Audio/眼保健操.mp3",
                displayName: "眼保健操",
                loop: false,
                volume: 0.8,
                durationSeconds: nil
            ),
            isEnabled: true
        )
        audioTask.countdownRemainingSeconds = 7
        engine.tasks = [audioTask]
        
        // Tick 1: 7s -> 6s（未进入预告区，无预告，未播放）
        engine.onTick()
        XCTAssertNil(engine.pendingAudioAlert, "尚余6秒，不应触发预告")
        XCTAssertEqual(engine.tasks.first?.effectiveTriggerCount, 0, "不应提前触发播放")
        
        // Tick 2: 6s -> 5s（触发预告，显示 5s，未播放）
        engine.onTick()
        XCTAssertNotNil(engine.pendingAudioAlert, "余5秒，应启动预告状态机")
        XCTAssertEqual(engine.pendingAudioAlert?.seconds, 5, "预告首秒必须足额显示 5s")
        XCTAssertEqual(engine.tasks.first?.effectiveTriggerCount, 0, "显示5s时不应提前播放")
        
        // Tick 3: 预告进入第 4 秒
        engine.onTick()
        XCTAssertEqual(engine.pendingAudioAlert?.seconds, 4)
        XCTAssertEqual(engine.tasks.first?.effectiveTriggerCount, 0)
        
        // Tick 4: 预告进入第 3 秒
        engine.onTick()
        XCTAssertEqual(engine.pendingAudioAlert?.seconds, 3)
        XCTAssertEqual(engine.tasks.first?.effectiveTriggerCount, 0)
        
        // Tick 5: 预告进入第 2 秒
        engine.onTick()
        XCTAssertEqual(engine.pendingAudioAlert?.seconds, 2)
        XCTAssertEqual(engine.tasks.first?.effectiveTriggerCount, 0)
        
        // Tick 6: 预告进入第 1 秒
        engine.onTick()
        XCTAssertEqual(engine.pendingAudioAlert?.seconds, 1)
        XCTAssertEqual(engine.tasks.first?.effectiveTriggerCount, 0)
        
        // Tick 7: 5s 倒计时完整结束（归零，预告关闭，正式触发播放）
        engine.onTick()
        XCTAssertNil(engine.pendingAudioAlert, "5秒倒数完毕后预告卡片应关闭")
        XCTAssertEqual(engine.tasks.first?.effectiveTriggerCount, 1, "必须在完整走完5秒后正式触发播放")
    }
    
    // MARK: - 短倒计时音频任务也能获得完整 5 秒跳过缓冲
    func testShortCountdownAudioPreAlertNeverPlaysEarly() {
        var shortTask = ScheduleTask(
            name: "短倒计时",
            trigger: .countdown(totalSeconds: 2),
            action: .playLocalAudio(
                filePath: "Resources/Audio/眼保健操.mp3",
                displayName: "眼保健操",
                loop: false,
                volume: 0.8,
                durationSeconds: nil
            ),
            isEnabled: true
        )
        shortTask.countdownRemainingSeconds = 2
        engine.tasks = [shortTask]
        
        // Tick 1: 剩余 1s <= 5s，立即启动预告（显示 5s，绝不立即播放）
        engine.onTick()
        XCTAssertEqual(engine.pendingAudioAlert?.seconds, 5)
        XCTAssertEqual(engine.tasks.first?.effectiveTriggerCount, 0)
        
        // Tick 2: 显示 4s
        engine.onTick()
        XCTAssertEqual(engine.pendingAudioAlert?.seconds, 4)
        XCTAssertEqual(engine.tasks.first?.effectiveTriggerCount, 0)
        
        // Tick 3: 显示 3s
        engine.onTick()
        XCTAssertEqual(engine.pendingAudioAlert?.seconds, 3)
        XCTAssertEqual(engine.tasks.first?.effectiveTriggerCount, 0)
        
        // Tick 4: 显示 2s
        engine.onTick()
        XCTAssertEqual(engine.pendingAudioAlert?.seconds, 2)
        XCTAssertEqual(engine.tasks.first?.effectiveTriggerCount, 0)
        
        // Tick 5: 显示 1s
        engine.onTick()
        XCTAssertEqual(engine.pendingAudioAlert?.seconds, 1)
        XCTAssertEqual(engine.tasks.first?.effectiveTriggerCount, 0)
        
        // Tick 6: 完整 5 秒结束，触发播放
        engine.onTick()
        XCTAssertNil(engine.pendingAudioAlert)
        XCTAssertEqual(engine.tasks.first?.effectiveTriggerCount, 1)
    }
    
    // MARK: - 息屏防打扰测试：屏幕息屏期间严禁触发任何任务
    func testScreenSleepSuppressesTaskTrigger() {
        let task = ScheduleTask(
            name: "眼保健操",
            trigger: .interval(intervalSeconds: 10),
            isEnabled: true
        )
        engine.tasks = [task]
        
        // 发送屏幕息屏通知
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        
        // 模拟息屏期间多次 tick
        engine.onTick()
        engine.onTick()
        
        // 验证任务没有被触发
        let currentTask = engine.tasks.first { $0.id == task.id }
        XCTAssertEqual(currentTask?.effectiveTriggerCount, 0, "息屏期间绝对不能触发任务与计入统计")
        
        // 发送屏幕亮屏通知
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
    }
}
