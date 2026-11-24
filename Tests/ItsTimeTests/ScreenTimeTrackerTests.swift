import XCTest
@testable import itstime

final class ScreenTimeTrackerTests: XCTestCase {
    
    @MainActor
    override func setUp() {
        super.setUp()
        ScreenTimeTrackerService.shared.clearTodayData()
    }
    
    func testAppUsageRecordFormatting() {
        let rec1 = AppUsageRecord(bundleIdentifier: "com.apple.dt.Xcode", appName: "Xcode", durationSeconds: 45)
        XCTAssertEqual(rec1.formattedDuration, "45秒")
        
        let rec2 = AppUsageRecord(bundleIdentifier: "com.google.Chrome", appName: "Chrome", durationSeconds: 150)
        XCTAssertEqual(rec2.formattedDuration, "2分钟")
        
        let rec3 = AppUsageRecord(bundleIdentifier: "com.apple.Terminal", appName: "Terminal", durationSeconds: 3750)
        XCTAssertEqual(rec3.formattedDuration, "1小时2分")
    }
    
    func testDailyScreenTimeRecordCalculations() {
        var daily = DailyScreenTimeRecord(dateString: "2026-11-24")
        daily.totalActiveSeconds = 7200
        
        daily.appUsages["app.a"] = AppUsageRecord(bundleIdentifier: "app.a", appName: "App A", durationSeconds: 1800, activationCount: 5)
        daily.appUsages["app.b"] = AppUsageRecord(bundleIdentifier: "app.b", appName: "App B", durationSeconds: 5400, activationCount: 12)
        
        XCTAssertEqual(daily.formattedTotalDuration, "2小时0分")
        XCTAssertEqual(daily.sortedApps.first?.bundleIdentifier, "app.b")
        XCTAssertEqual(daily.sortedApps.first?.activationCount, 12)
    }
    
    @MainActor
    func testEventTriggerTracking() {
        let task = ScheduleTask(
            name: "喝水提醒",
            trigger: .interval(intervalSeconds: 1800)
        )
        
        let tracker = ScreenTimeTrackerService.shared
        tracker.recordEventTrigger(for: task)
        tracker.recordEventTrigger(for: task)
        
        XCTAssertEqual(tracker.todayTotalEventTriggerCount, 2)
        XCTAssertEqual(tracker.todaySortedEventTriggers.first?.count, 2)
        XCTAssertEqual(tracker.todaySortedEventTriggers.first?.taskName, "喝水提醒")
    }
    
    @MainActor
    func testSchedulerEngineTriggerIncrementsTaskCount() {
        let engine = SchedulerEngine.shared
        let taskId = UUID()
        let task = ScheduleTask(
            id: taskId,
            name: "站立拉伸",
            trigger: .countdown(totalSeconds: 10),
            triggerCount: 0
        )
        engine.tasks.append(task)
        
        XCTAssertEqual(task.effectiveTriggerCount, 0)
        
        // 模拟触发动作
        engine.executeAction(for: task)
        
        // 验证 engine 中的任务计数增加
        if let updatedTask = engine.tasks.first(where: { $0.id == taskId }) {
            XCTAssertEqual(updatedTask.effectiveTriggerCount, 1)
        } else {
            XCTFail("Task should exist in scheduler engine")
        }
        
        // 清理测试任务
        engine.tasks.removeAll(where: { $0.id == taskId })
    }
    
    @MainActor
    func testIdleThresholdConstant() {
        // 用户要求：无操作超过 5 分钟，将暂停计入活跃时间
        XCTAssertEqual(ScreenTimeTrackerService.idleThresholdSeconds, 300.0)
    }
    
    @MainActor
    func testIconCachingMechanism() {
        let tracker = ScreenTimeTrackerService.shared
        let icon1 = tracker.icon(for: "com.apple.finder")
        let icon2 = tracker.icon(for: "com.apple.finder")
        
        // 缓存命中同一指针或相同图像实例
        XCTAssertEqual(icon1.size, icon2.size)
        
        let unknownIcon = tracker.icon(for: "nonexistent.fake.bundle.id")
        XCTAssertNotNil(unknownIcon)
    }
    
    @MainActor
    func testEventTriggerSuppressedWhenScreenIsAsleep() {
        let tracker = ScreenTimeTrackerService.shared
        let task = ScheduleTask(name: "息屏眼保健操", trigger: .interval(intervalSeconds: 60))
        
        let initialCount = tracker.todayTotalEventTriggerCount
        // 模拟通过 NSWorkspace 通知中心发送息屏通知
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        
        tracker.recordEventTrigger(for: task)
        
        XCTAssertEqual(tracker.todayTotalEventTriggerCount, initialCount, "息屏期间 recordEventTrigger 绝不能累加")
        
        // 恢复亮屏
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
    }
    
    @MainActor
    func testTimeScopeAggregation() {
        let tracker = ScreenTimeTrackerService.shared
        tracker.recordAppUsageForTesting(bundleId: "com.apple.dt.Xcode", appName: "Xcode", duration: 3600, activations: 4)
        
        let dayStats = tracker.calculateStats(for: .day)
        XCTAssertEqual(dayStats.scope, .day)
        XCTAssertGreaterThanOrEqual(dayStats.totalActiveSeconds, 3600)
        XCTAssertEqual(dayStats.sortedApps.first?.bundleIdentifier, "com.apple.dt.Xcode")
        
        let weekStats = tracker.calculateStats(for: .week)
        XCTAssertEqual(weekStats.scope, .week)
        XCTAssertGreaterThanOrEqual(weekStats.totalActiveSeconds, 3600)
        
        let monthStats = tracker.calculateStats(for: .month)
        XCTAssertEqual(monthStats.scope, .month)
        
        let yearStats = tracker.calculateStats(for: .year)
        XCTAssertEqual(yearStats.scope, .year)
    }
    
    @MainActor
    func testHistoricalDateNavigation() {
        let tracker = ScreenTimeTrackerService.shared
        tracker.selectedScope = .day
        tracker.goToToday()
        
        XCTAssertFalse(tracker.canGoNext, "今天不可向未来翻页")
        XCTAssertTrue(tracker.isCurrentPeriod)
        
        // 向前翻到昨天
        tracker.goToPrevious()
        XCTAssertTrue(tracker.canGoNext, "翻到历史日期后允许向后翻页")
        XCTAssertFalse(tracker.isCurrentPeriod)
        
        // 往后翻回到今天
        tracker.goToNext()
        XCTAssertFalse(tracker.canGoNext)
        XCTAssertTrue(tracker.isCurrentPeriod)
        
        // 直接选择特定历史日期
        let calendar = Calendar.current
        let targetPastDate = calendar.date(byAdding: .day, value: -10, to: Date())!
        tracker.selectDate(targetPastDate)
        XCTAssertEqual(calendar.startOfDay(for: tracker.anchorDate), calendar.startOfDay(for: targetPastDate))
        
        // 一键回今天
        tracker.goToToday()
        XCTAssertTrue(tracker.isCurrentPeriod)
    }
    
    @MainActor
    func testHistoricalStatsLoadingAndClearing() {
        let tracker = ScreenTimeTrackerService.shared
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let yesterdayStr = df.string(from: yesterday)
        
        // 构造昨天的历史数据并持久化
        var yesterdayRecord = DailyScreenTimeRecord(dateString: yesterdayStr)
        yesterdayRecord.totalActiveSeconds = 5400
        yesterdayRecord.appUsages["com.apple.Safari"] = AppUsageRecord(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari",
            durationSeconds: 5400,
            activationCount: 8
        )
        let key = "ItsTime_ScreenTime_" + yesterdayStr
        let data = try! JSONEncoder().encode(yesterdayRecord)
        UserDefaults.standard.set(data, forKey: key)
        
        // 切换到昨天
        tracker.selectDate(yesterday)
        let stats = tracker.calculateStats(for: .day, anchor: yesterday)
        XCTAssertEqual(stats.totalActiveSeconds, 5400)
        XCTAssertEqual(stats.sortedApps.first?.bundleIdentifier, "com.apple.Safari")
        
        // 清理昨天数据
        tracker.clearCurrentDateData()
        let clearedStats = tracker.calculateStats(for: .day, anchor: yesterday)
        XCTAssertEqual(clearedStats.totalActiveSeconds, 0)
        
        // 恢复锚点到今天
        tracker.goToToday()
    }
    
    @MainActor
    func testPastEventLogsRecordedAndAggregated() {
        let tracker = ScreenTimeTrackerService.shared
        tracker.clearTodayData()
        
        let task1 = ScheduleTask(
            name: "喝水提醒",
            trigger: .interval(intervalSeconds: 1800)
        )
        let task2 = ScheduleTask(
            name: "团队站会",
            trigger: .daily(hour: 10, minute: 0)
        )
        
        tracker.recordEventTrigger(for: task1)
        tracker.recordEventTrigger(for: task2)
        
        let stats = tracker.currentStats
        XCTAssertEqual(stats.pastEventLogs.count, 2)
        XCTAssertEqual(stats.pastEventLogs[0].taskName, "喝水提醒")
        XCTAssertEqual(stats.pastEventLogs[0].kindString, "interval")
        XCTAssertEqual(stats.pastEventLogs[1].taskName, "团队站会")
        XCTAssertEqual(stats.pastEventLogs[1].kindString, "daily")
    }
}
