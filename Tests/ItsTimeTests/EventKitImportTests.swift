import XCTest
@testable import itstime

final class EventKitImportTests: XCTestCase {
    
    // MARK: - 智能链接提取测试
    func testExtractURLFromPrimaryURL() {
        let directURL = URL(string: "https://zoom.us/j/123456789")
        let extracted = EventKitService.extractURL(
            primaryURL: directURL,
            notes: "备注内容",
            title: "普通标题"
        )
        XCTAssertEqual(extracted?.absoluteString, "https://zoom.us/j/123456789")
    }
    
    func testExtractURLFromNotes() {
        let notes = "会议主题：周会\n加入链接：https://meeting.tencent.com/dm/abc123xyz\n密码：1234"
        let extracted = EventKitService.extractURL(
            primaryURL: nil,
            notes: notes,
            title: "产品周会"
        )
        XCTAssertEqual(extracted?.absoluteString, "https://meeting.tencent.com/dm/abc123xyz")
    }
    
    func testExtractURLFromLocation() {
        let location = "https://feishu.cn/j/998877"
        let extracted = EventKitService.extractURL(
            primaryURL: nil,
            notes: nil,
            location: location,
            title: "跨团队评审"
        )
        XCTAssertEqual(extracted?.absoluteString, "https://feishu.cn/j/998877")
    }
    
    func testExtractURLFromTitle() {
        let title = "点击参加 https://meet.google.com/xyz-qwe-rty 线上访谈"
        let extracted = EventKitService.extractURL(
            primaryURL: nil,
            notes: nil,
            title: title
        )
        XCTAssertEqual(extracted?.absoluteString, "https://meet.google.com/xyz-qwe-rty")
    }
    
    func testExtractURLWhenNoURLPresent() {
        let extracted = EventKitService.extractURL(
            primaryURL: nil,
            notes: "今天记得买牛奶和面包",
            title: "购物清单"
        )
        XCTAssertNil(extracted)
    }
    
    // MARK: - 提醒事项数据模型时间解析测试
    func testSystemReminderTaskTiming() {
        // 1. 无时间提醒事项
        let noTimeTask = SystemReminderTask(
            id: "1",
            title: "整理桌面",
            dueDate: nil,
            hasSpecificTime: false
        )
        XCTAssertFalse(noTimeTask.hasSpecificTime)
        XCTAssertFalse(noTimeTask.isOverdue)
        XCTAssertEqual(noTimeTask.formattedTime, "无具体时间")
        
        // 2. 全天事项（比如今天，但没有指定具体时分）
        let allDayTask = SystemReminderTask(
            id: "2",
            title: "提交报销单",
            dueDate: Date(),
            hasSpecificTime: false
        )
        XCTAssertFalse(allDayTask.hasSpecificTime)
        XCTAssertFalse(allDayTask.isOverdue)
        XCTAssertTrue(allDayTask.formattedTime.contains("全天"))
        
        // 3. 未来明确时分
        let futureDate = Date().addingTimeInterval(3600)
        let futureTask = SystemReminderTask(
            id: "3",
            title: "与客户电话",
            dueDate: futureDate,
            hasSpecificTime: true,
            url: URL(string: "https://example.com/call")
        )
        XCTAssertTrue(futureTask.hasSpecificTime)
        XCTAssertFalse(futureTask.isOverdue)
        XCTAssertNotNil(futureTask.url)
        
        // 4. 过去已逾期事项
        let pastDate = Date().addingTimeInterval(-3600)
        let overdueTask = SystemReminderTask(
            id: "4",
            title: "早会",
            dueDate: pastDate,
            hasSpecificTime: true
        )
        XCTAssertTrue(overdueTask.hasSpecificTime)
        XCTAssertTrue(overdueTask.isOverdue)
        XCTAssertTrue(overdueTask.formattedTime.contains("已逾期"))
    }
    
    // MARK: - 日历事件状态与导入识别测试
    func testCalendarEventStatusCalculation() {
        let now = Date()
        
        // 过去事件
        let pastEvent = SystemCalendarEvent(
            id: "ev1",
            title: "上午例会",
            startDate: now.addingTimeInterval(-7200),
            endDate: now.addingTimeInterval(-3600),
            url: nil,
            location: nil,
            isAllDay: false
        )
        XCTAssertTrue(pastEvent.isPast)
        XCTAssertFalse(pastEvent.isOngoing)
        XCTAssertFalse(pastEvent.isUpcoming)
        
        // 进行中事件
        let ongoingEvent = SystemCalendarEvent(
            id: "ev2",
            title: "头脑风暴",
            startDate: now.addingTimeInterval(-1800),
            endDate: now.addingTimeInterval(1800),
            url: URL(string: "https://zoom.us/j/123"),
            location: nil,
            isAllDay: false
        )
        XCTAssertFalse(ongoingEvent.isPast)
        XCTAssertTrue(ongoingEvent.isOngoing)
        XCTAssertFalse(ongoingEvent.isUpcoming)
        
        // 即将到来事件
        let upcomingEvent = SystemCalendarEvent(
            id: "ev3",
            title: "产品评审",
            startDate: now.addingTimeInterval(3600),
            endDate: now.addingTimeInterval(7200),
            url: nil,
            location: nil,
            isAllDay: false
        )
        XCTAssertFalse(upcomingEvent.isPast)
        XCTAssertFalse(upcomingEvent.isOngoing)
        XCTAssertTrue(upcomingEvent.isUpcoming)
    }
    
    func testIsCalendarEventImportedDetection() {
        let eventDate = Date().addingTimeInterval(3600)
        let comps = Calendar.current.dateComponents([.hour, .minute], from: eventDate)
        
        let event = SystemCalendarEvent(
            id: "ev10",
            title: "架构方案讨论",
            startDate: eventDate,
            endDate: eventDate.addingTimeInterval(1800),
            url: nil,
            location: nil,
            isAllDay: false
        )
        
        // 1. 无对应任务时返回 false
        let unrelatedTask = ScheduleTask(
            name: "喝水",
            trigger: .interval(intervalSeconds: 1800),
            action: .none
        )
        XCTAssertFalse(EventKitService.isCalendarEventImported(event: event, tasks: [unrelatedTask]))
        
        // 2. 存在匹配时刻的单次任务时返回 true
        let matchedOnceTask = ScheduleTask(
            name: "架构方案讨论",
            trigger: .once(eventDate),
            action: .none
        )
        XCTAssertTrue(EventKitService.isCalendarEventImported(event: event, tasks: [matchedOnceTask]))
        
        // 3. 存在匹配时刻的每日任务时返回 true
        let matchedDailyTask = ScheduleTask(
            name: "架构方案讨论",
            trigger: .daily(hour: comps.hour ?? 0, minute: comps.minute ?? 0),
            action: .none
        )
        XCTAssertTrue(EventKitService.isCalendarEventImported(event: event, tasks: [matchedDailyTask]))
    }
    
    func testSearchResultSuggestedHourMinute() {
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 16
        comps.minute = 45
        let date = calendar.date(from: comps)!
        
        let ev = SystemCalendarEvent(
            id: "ev20",
            title: "项目对齐会",
            startDate: date,
            endDate: date.addingTimeInterval(1800),
            url: URL(string: "https://meeting.tencent.com/dm/1234"),
            location: nil,
            isAllDay: false
        )
        
        let result = EventKitSearchResult.calendar(event: ev)
        let extractedHM = result.suggestedHourMinute
        XCTAssertNotNil(extractedHM)
        XCTAssertEqual(extractedHM?.hour, 16)
        XCTAssertEqual(extractedHM?.minute, 45)
    }
}
