import XCTest
@testable import itstime

final class TriggerCalculationTests: XCTestCase {
    
    // MARK: - 倒计时计算与状态流转
    func testCountdownNextTriggerDate() {
        let baseDate = Date(timeIntervalSince1970: 1700000000)
        
        // 1. 正常启用状态的倒计时
        let task = ScheduleTask(
            name: "深度专注",
            trigger: .countdown(totalSeconds: 1500), // 25分钟
            isEnabled: true,
            isPaused: false
        )
        let nextDate = task.calculateNextTriggerDate(from: baseDate)
        XCTAssertNotNil(nextDate)
        XCTAssertEqual(nextDate?.timeIntervalSince(baseDate), 1500)
        
        // 2. 暂停状态应返回 nil
        var pausedTask = task
        pausedTask.isPaused = true
        XCTAssertNil(pausedTask.calculateNextTriggerDate(from: baseDate))
        
        // 3. 禁用状态应返回 nil
        var disabledTask = task
        disabledTask.isEnabled = false
        XCTAssertNil(disabledTask.calculateNextTriggerDate(from: baseDate))
        
        // 4. 进行中的倒计时（已流逝部分时间）
        var runningTask = task
        runningTask.countdownRemainingSeconds = 300 // 剩余 5 分钟
        let runningNext = runningTask.calculateNextTriggerDate(from: baseDate)
        XCTAssertEqual(runningNext?.timeIntervalSince(baseDate), 300)
    }
    
    // MARK: - 每日固定时刻（当天未过 vs 当天已过）
    func testDailyScheduleNextTriggerDate() {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        
        // 设定基准日期为 2026-11-23 10:00:00
        var baseComponents = DateComponents()
        baseComponents.year = 2026
        baseComponents.month = 11
        baseComponents.day = 23
        baseComponents.hour = 10
        baseComponents.minute = 0
        baseComponents.second = 0
        guard let baseDate = calendar.date(from: baseComponents) else {
            XCTFail("无法生成基准测试日期")
            return
        }
        
        // 1. 当天未来时刻：16:00 (尚未到)，应返回今天的 16:00
        let afternoonTask = ScheduleTask(
            name: "八段锦",
            trigger: .daily(hour: 16, minute: 0),
            isEnabled: true
        )
        let afternoonNext = afternoonTask.calculateNextTriggerDate(from: baseDate)
        XCTAssertNotNil(afternoonNext)
        let afternoonComps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: afternoonNext!)
        XCTAssertEqual(afternoonComps.year, 2026)
        XCTAssertEqual(afternoonComps.month, 11)
        XCTAssertEqual(afternoonComps.day, 23)
        XCTAssertEqual(afternoonComps.hour, 16)
        XCTAssertEqual(afternoonComps.minute, 0)
        
        // 2. 当天已过时刻：09:30 (已过)，应返回明天的 09:30 (2026-11-24)
        let morningTask = ScheduleTask(
            name: "团队晨会",
            trigger: .daily(hour: 9, minute: 30),
            isEnabled: true
        )
        let morningNext = morningTask.calculateNextTriggerDate(from: baseDate)
        XCTAssertNotNil(morningNext)
        let morningComps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: morningNext!)
        XCTAssertEqual(morningComps.year, 2026)
        XCTAssertEqual(morningComps.month, 11)
        XCTAssertEqual(morningComps.day, 24)
        XCTAssertEqual(morningComps.hour, 9)
        XCTAssertEqual(morningComps.minute, 30)
    }
    
    // MARK: - 循环间隔（Interval）触发计算
    func testIntervalNextTriggerDate() {
        let baseDate = Date(timeIntervalSince1970: 1700000000)
        
        // 1. 从未触发过，基于 createdAt 顺延
        let task = ScheduleTask(
            name: "护眼提醒",
            trigger: .interval(intervalSeconds: 1800), // 30分钟
            isEnabled: true,
            createdAt: baseDate
        )
        let firstNext = task.calculateNextTriggerDate(from: baseDate)
        XCTAssertEqual(firstNext?.timeIntervalSince(baseDate), 1800)
        
        // 2. 已触发过，基于 lastTriggeredAt 顺延
        var triggeredTask = task
        let lastTriggerTime = baseDate.addingTimeInterval(600)
        triggeredTask.lastTriggeredAt = lastTriggerTime
        let secondNext = triggeredTask.calculateNextTriggerDate(from: baseDate)
        XCTAssertEqual(secondNext?.timeIntervalSince(lastTriggerTime), 1800)
    }
    
    // MARK: - 触发器展示文本格式化（包容神经多样性与清晰度）
    func testTriggerDisplayTitle() {
        // 倒计时
        XCTAssertEqual(TriggerType.countdown(totalSeconds: 1500).displayTitle, "25 分钟")
        XCTAssertEqual(TriggerType.countdown(totalSeconds: 90).displayTitle, "1分30秒")
        XCTAssertEqual(TriggerType.countdown(totalSeconds: 45).displayTitle, "0分45秒")
        
        // 每日固定时刻
        XCTAssertEqual(TriggerType.daily(hour: 9, minute: 5).displayTitle, "每天 09:05")
        XCTAssertEqual(TriggerType.daily(hour: 18, minute: 30).displayTitle, "每天 18:30")
        
        // 循环间隔
        XCTAssertEqual(TriggerType.interval(intervalSeconds: 30).displayTitle, "每 30 秒")
        XCTAssertEqual(TriggerType.interval(intervalSeconds: 1800).displayTitle, "每 30 分钟")
        XCTAssertEqual(TriggerType.interval(intervalSeconds: 7200).displayTitle, "每 2 小时")
        XCTAssertEqual(TriggerType.interval(intervalSeconds: 90).displayTitle, "每 1分30秒")
    }
}
