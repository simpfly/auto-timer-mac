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
        
        // 模拟提前 3 秒检测到了预告
        AudioPreAlertHUD.shared.update(
            alert: AudioPreAlertInfo(
                taskId: audioTask.id,
                taskName: audioTask.name,
                audioName: "八段锦",
                secondsRemaining: 3
            )
        )
        
        // 模拟内部设置 pendingAudioAlert
        // 验证用户在气泡上点击“跳过本次”
        engine.skipAudioPreAlert()
        XCTAssertNil(engine.pendingAudioAlert)
    }
}
