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
    
    @MainActor
    func testScopeBucketsGeneration() {
        let tracker = ScreenTimeTrackerService.shared
        tracker.clearTodayData()
        tracker.goToToday()
        tracker.recordAppUsageForTesting(bundleId: "com.apple.dt.Xcode", appName: "Xcode", duration: 3600)
        
        let dayStats = tracker.calculateStats(for: .day)
        XCTAssertTrue(dayStats.buckets.isEmpty)
        
        let weekStats = tracker.calculateStats(for: .week)
        XCTAssertEqual(weekStats.buckets.count, 7)
        XCTAssertEqual(weekStats.buckets.reduce(0) { $0 + $1.durationSeconds }, weekStats.totalActiveSeconds, accuracy: 0.01)
        
        let monthStats = tracker.calculateStats(for: .month)
        let daysInMonth = Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30
        XCTAssertEqual(monthStats.buckets.count, daysInMonth)
        XCTAssertEqual(monthStats.buckets.reduce(0) { $0 + $1.durationSeconds }, monthStats.totalActiveSeconds, accuracy: 0.01)
        
        let yearStats = tracker.calculateStats(for: .year)
        XCTAssertEqual(yearStats.buckets.count, 12)
        XCTAssertEqual(yearStats.buckets.reduce(0) { $0 + $1.durationSeconds }, yearStats.totalActiveSeconds, accuracy: 0.01)
    }
    
    @MainActor
    func testAudioPlaybackPreventsIdleAndAccumulatesActiveTime() {
        let tracker = ScreenTimeTrackerService.shared
        tracker.clearTodayData()
        tracker.isTrackingEnabled = true
        tracker.recordAppUsageForTesting(bundleId: "com.apple.Safari", appName: "Safari", duration: 0, activations: 1)
        
        let baseDate = Date()
        tracker.lastActiveTimestamp = baseDate.addingTimeInterval(-10)
        
        // 无操作超过 300s，但扬声器正在播放 → 应保持活跃，计入活跃时长
        tracker.processHeartbeat(idleSeconds: 400, isPlayingAudio: true, now: baseDate)
        XCTAssertFalse(tracker.isUserIdle)
        XCTAssertEqual(tracker.todayTotalSeconds, 10, accuracy: 0.1)
        XCTAssertEqual(tracker.todayIdleSeconds, 0, accuracy: 0.1)
        
        // 停止播放且无操作超过 300s → 应进入闲置，计入亮屏闲置时长
        tracker.lastActiveTimestamp = baseDate
        tracker.processHeartbeat(idleSeconds: 400, isPlayingAudio: false, now: baseDate.addingTimeInterval(15))
        XCTAssertTrue(tracker.isUserIdle)
        XCTAssertEqual(tracker.todayTotalSeconds, 10, accuracy: 0.1)
        XCTAssertEqual(tracker.todayIdleSeconds, 15, accuracy: 0.1)
        XCTAssertEqual(tracker.calculateStats(for: .day).totalIdleSeconds, 15, accuracy: 0.1)
    }
    
    func testLegacyDailyRecordDecodingWithoutIdleSeconds() throws {
        let legacyJSON = """
        {
            "dateString": "2026-11-20",
            "totalActiveSeconds": 1200,
            "appUsages": {},
            "eventTriggers": []
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DailyScreenTimeRecord.self, from: legacyJSON)
        XCTAssertEqual(decoded.totalActiveSeconds, 1200)
        XCTAssertEqual(decoded.totalIdleSeconds, 0)
    }
    
    @MainActor
    func testSkipPreAlertAndManualTestDoNotRecordTrigger() {
        let tracker = ScreenTimeTrackerService.shared
        let engine = SchedulerEngine.shared
        tracker.clearTodayData()
        
        let taskId = UUID()
        let task = ScheduleTask(
            id: taskId,
            name: "测试护眼",
            trigger: .interval(intervalSeconds: 2700),
            action: .none,
            triggerCount: 0
        )
        engine.tasks.append(task)
        
        // 1. 预告卡片点击【不播放】如实记录为「已忽略」
        engine.startAudioPreAlert(for: task)
        engine.skipAudioPreAlert()
        XCTAssertEqual(tracker.todayTotalEventTriggerCount, 1)
        XCTAssertEqual(tracker.currentStats.pastEventLogs.count, 1)
        XCTAssertEqual(tracker.currentStats.pastEventLogs.first?.effectiveIsIgnored, true)
        XCTAssertEqual(tracker.currentStats.sortedEventTriggers.first?.effectiveIgnoredCount, 1)
        XCTAssertEqual(tracker.currentStats.sortedEventTriggers.first?.effectiveDoneCount, 0)
        XCTAssertEqual(engine.tasks.first(where: { $0.id == taskId })?.effectiveTriggerCount, 1)
        
        // 2. 卡片点击【测试运行】不应记录正式触发次数与日志
        engine.executeAction(for: task, isManualTest: true)
        XCTAssertEqual(tracker.todayTotalEventTriggerCount, 1)
        XCTAssertEqual(tracker.currentStats.pastEventLogs.count, 1)
        XCTAssertEqual(engine.tasks.first(where: { $0.id == taskId })?.effectiveTriggerCount, 1)
        
        engine.tasks.removeAll(where: { $0.id == taskId })
    }
    
    @MainActor
    func testEventLogIgnoreAndDoneTracking() throws {
        let tracker = ScreenTimeTrackerService.shared
        tracker.clearTodayData()
        
        let task = ScheduleTask(
            name: "喝水提醒",
            trigger: .interval(intervalSeconds: 1800),
            action: .popupContent(mode: .textNotification(message: "喝杯水"))
        )
        
        let logId1 = try XCTUnwrap(tracker.recordEventTrigger(for: task))
        let logId2 = try XCTUnwrap(tracker.recordEventTrigger(for: task))
        XCTAssertNotEqual(logId1, logId2)
        
        // 将第二次触发标记为忽略（幂等验证：重复调用不应重复累加）
        tracker.markEventLogIgnored(logId: logId2)
        tracker.markEventLogIgnored(logId: logId2)
        
        let stats = tracker.currentStats
        XCTAssertEqual(stats.pastEventLogs.count, 2)
        XCTAssertEqual(stats.pastEventLogs.first(where: { $0.id == logId1 })?.effectiveIsIgnored, false)
        XCTAssertEqual(stats.pastEventLogs.first(where: { $0.id == logId2 })?.effectiveIsIgnored, true)
        
        let triggerRecord = try XCTUnwrap(stats.sortedEventTriggers.first(where: { $0.id == task.id }))
        XCTAssertEqual(triggerRecord.count, 2)
        XCTAssertEqual(triggerRecord.effectiveIgnoredCount, 1)
        XCTAssertEqual(triggerRecord.effectiveDoneCount, 1)
    }
    
    func testLegacyEventRecordDecodingWithoutIgnoredFields() throws {
        let legacyLogJSON = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "taskName": "旧版提醒",
            "triggerTypeTitle": "每 30 分钟",
            "timestamp": 0,
            "kindString": "interval",
            "actionDesc": "文本提示"
        }
        """.data(using: .utf8)!
        let decodedLog = try JSONDecoder().decode(PastEventLogItem.self, from: legacyLogJSON)
        XCTAssertNil(decodedLog.isIgnored)
        XCTAssertFalse(decodedLog.effectiveIsIgnored)
        
        let legacyTriggerJSON = """
        {
            "id": "22222222-2222-2222-2222-222222222222",
            "taskName": "旧版提醒",
            "triggerTypeTitle": "每 30 分钟",
            "count": 3,
            "lastTriggeredAt": 0
        }
        """.data(using: .utf8)!
        let decodedTrigger = try JSONDecoder().decode(EventTriggerRecord.self, from: legacyTriggerJSON)
        XCTAssertNil(decodedTrigger.ignoredCount)
        XCTAssertEqual(decodedTrigger.effectiveIgnoredCount, 0)
        XCTAssertEqual(decodedTrigger.effectiveDoneCount, 3)
    }
}
