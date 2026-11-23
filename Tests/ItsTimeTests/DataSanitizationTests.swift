import XCTest
@testable import itstime

final class DataSanitizationTests: XCTestCase {
    
    // MARK: - URL 自动补全与协议安全测试
    func testSanitizeURLString() {
        // 1. 无前缀的纯域名，自动补全 https://
        let result1 = ScheduleTask.sanitizeURLString("github.com/simpfly/its-time-mac")
        XCTAssertEqual(result1.formatted, "https://github.com/simpfly/its-time-mac")
        XCTAssertNotNil(result1.url)
        XCTAssertEqual(result1.url?.scheme, "https")
        
        // 2. 带空格输入的域名，前后空格被剔除并补全
        let result2 = ScheduleTask.sanitizeURLString("   feishu.cn/meeting/123   \n")
        XCTAssertEqual(result2.formatted, "https://feishu.cn/meeting/123")
        XCTAssertNotNil(result2.url)
        
        // 3. 原本就是 https:// 的链接，保持原样
        let result3 = ScheduleTask.sanitizeURLString("https://linear.app")
        XCTAssertEqual(result3.formatted, "https://linear.app")
        XCTAssertEqual(result3.url?.host, "linear.app")
        
        // 4. http:// 协议正常保留
        let result4 = ScheduleTask.sanitizeURLString("http://localhost:3000")
        XCTAssertEqual(result4.formatted, "http://localhost:3000")
        XCTAssertEqual(result4.url?.scheme, "http")
    }
    
    // MARK: - ScheduleTask 序列化与反序列化（Codable）测试
    func testScheduleTaskCodableRoundtrip() throws {
        let originalTask = ScheduleTask(
            id: UUID(),
            name: "自动化测试任务",
            trigger: .daily(hour: 14, minute: 30),
            action: .popupContent(mode: .customChecklist(items: [
                ChecklistItem(text: "检查站立姿态", isCompleted: true),
                ChecklistItem(text: "补充 300ml 温水", isCompleted: false)
            ])),
            isEnabled: true,
            isPaused: false,
            createdAt: Date()
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalTask)
        
        let decoder = JSONDecoder()
        let decodedTask = try decoder.decode(ScheduleTask.self, from: data)
        
        XCTAssertEqual(decodedTask.id, originalTask.id)
        XCTAssertEqual(decodedTask.name, originalTask.name)
        XCTAssertEqual(decodedTask.trigger, originalTask.trigger)
        XCTAssertEqual(decodedTask.action, originalTask.action)
        XCTAssertEqual(decodedTask.isEnabled, originalTask.isEnabled)
        XCTAssertEqual(decodedTask.isPaused, originalTask.isPaused)
    }
    
    // MARK: - ActionType 摘要文案清晰度测试
    func testActionTypeSummary() {
        XCTAssertEqual(ActionType.none.summary, "声音通知")
        XCTAssertEqual(ActionType.popupContent(mode: .textNotification(message: "起身活动")).summary, "文本提示")
        XCTAssertEqual(ActionType.popupContent(mode: .todaySystemAgenda).summary, "今日日程")
        
        let checklistAction = ActionType.popupContent(mode: .customChecklist(items: [
            ChecklistItem(text: "项目1"),
            ChecklistItem(text: "项目2")
        ]))
        XCTAssertEqual(checklistAction.summary, "清单 (2项)")
        
        let audioAction = ActionType.playLocalAudio(
            filePath: "Resources/Audio/眼保健操.mp3",
            displayName: "眼保健操",
            loop: true,
            volume: 0.8,
            durationSeconds: 300
        )
        XCTAssertEqual(audioAction.summary, "眼保健操 (循环) (5分钟)")
        
        let urlAction = ActionType.openURL(urlString: "https://linear.app/inbox")
        XCTAssertEqual(urlAction.summary, "linear.app/inbox")
    }
}
