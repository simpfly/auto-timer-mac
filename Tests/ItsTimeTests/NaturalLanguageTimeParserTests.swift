import XCTest
@testable import itstime

final class NaturalLanguageTimeParserTests: XCTestCase {
    
    let parser = NaturalLanguageTimeParser.shared
    
    // MARK: - 倒计时解析测试
    func testCountdownParsing() {
        // 1. 常见分钟倒计时
        let res1 = parser.parse("25分钟后开会")
        XCTAssertNotNil(res1)
        XCTAssertEqual(res1?.mode, .countdown(minutes: 25, seconds: 0))
        XCTAssertEqual(res1?.cleanedTitle, "开会")
        
        // 2. 秒级倒计时
        let res2 = parser.parse("45秒后")
        XCTAssertNotNil(res2)
        XCTAssertEqual(res2?.mode, .countdown(minutes: 0, seconds: 45))
        XCTAssertEqual(res2?.cleanedTitle, "")
        
        // 3. 半小时
        let res3 = parser.parse("半小时后去吃饭")
        XCTAssertNotNil(res3)
        XCTAssertEqual(res3?.mode, .countdown(minutes: 30, seconds: 0))
        XCTAssertEqual(res3?.cleanedTitle, "去吃饭")
        
        // 4. 小时+分钟复合
        let res4 = parser.parse("1小时20分 整理周报")
        XCTAssertNotNil(res4)
        XCTAssertEqual(res4?.mode, .countdown(minutes: 80, seconds: 0))
        XCTAssertEqual(res4?.cleanedTitle, "整理周报")
        
        // 5. 英文简写 (30s, 15m)
        let res5 = parser.parse("30s 泡茶")
        XCTAssertNotNil(res5)
        XCTAssertEqual(res5?.mode, .countdown(minutes: 0, seconds: 30))
        XCTAssertEqual(res5?.cleanedTitle, "泡茶")
        
        let res6 = parser.parse("15m 站立")
        XCTAssertNotNil(res6)
        XCTAssertEqual(res6?.mode, .countdown(minutes: 15, seconds: 0))
        XCTAssertEqual(res6?.cleanedTitle, "站立")
        
        // 6. 中文数字倒计时
        let res7 = parser.parse("二十分钟后开会")
        XCTAssertNotNil(res7)
        XCTAssertEqual(res7?.mode, .countdown(minutes: 20, seconds: 0))
        XCTAssertEqual(res7?.cleanedTitle, "开会")
    }
    
    // MARK: - 每日定时解析测试
    func testDailyTimeParsing() {
        // 1. 每天上午9点
        let res1 = parser.parse("每天上午9点晨会")
        XCTAssertNotNil(res1)
        XCTAssertEqual(res1?.mode, .daily(hour: 9, minute: 0))
        XCTAssertEqual(res1?.cleanedTitle, "晨会")
        
        // 2. 下午三点半
        let res2 = parser.parse("下午3点半喝咖啡")
        XCTAssertNotNil(res2)
        XCTAssertEqual(res2?.mode, .daily(hour: 15, minute: 30))
        XCTAssertEqual(res2?.cleanedTitle, "喝咖啡")
        
        // 3. 晚上8点
        let res3 = parser.parse("晚上8点读英语")
        XCTAssertNotNil(res3)
        XCTAssertEqual(res3?.mode, .daily(hour: 20, minute: 0))
        XCTAssertEqual(res3?.cleanedTitle, "读英语")
        
        // 4. 24小时制冒号时间
        let res4 = parser.parse("15:45 需求评审")
        XCTAssertNotNil(res4)
        XCTAssertEqual(res4?.mode, .daily(hour: 15, minute: 45))
        XCTAssertEqual(res4?.cleanedTitle, "需求评审")
        
        // 5. 中文数字: 下午三点
        let res5 = parser.parse("下午三点开会")
        XCTAssertNotNil(res5)
        XCTAssertEqual(res5?.mode, .daily(hour: 15, minute: 0))
        XCTAssertEqual(res5?.cleanedTitle, "开会")
        
        // 6. 中文全角冒号
        let res6 = parser.parse("15：30 喝水")
        XCTAssertNotNil(res6)
        XCTAssertEqual(res6?.mode, .daily(hour: 15, minute: 30))
        XCTAssertEqual(res6?.cleanedTitle, "喝水")
    }
    
    // MARK: - 循环间隔解析测试
    func testIntervalParsing() {
        // 1. 每30分钟
        let res1 = parser.parse("每30分钟喝水")
        XCTAssertNotNil(res1)
        XCTAssertEqual(res1?.mode, .interval(minutes: 30, seconds: 0))
        XCTAssertEqual(res1?.cleanedTitle, "喝水")
        
        // 2. 每隔45分钟
        let res2 = parser.parse("每隔45分钟站立一下")
        XCTAssertNotNil(res2)
        XCTAssertEqual(res2?.mode, .interval(minutes: 45, seconds: 0))
        XCTAssertEqual(res2?.cleanedTitle, "站立一下")
        
        // 3. 每半小时
        let res3 = parser.parse("每半小时休息")
        XCTAssertNotNil(res3)
        XCTAssertEqual(res3?.mode, .interval(minutes: 30, seconds: 0))
        XCTAssertEqual(res3?.cleanedTitle, "休息")
        
        // 4. 每1小时
        let res4 = parser.parse("每1小时活动肩颈")
        XCTAssertNotNil(res4)
        XCTAssertEqual(res4?.mode, .interval(minutes: 60, seconds: 0))
        XCTAssertEqual(res4?.cleanedTitle, "活动肩颈")
        
        // 5. 每15秒
        let res5 = parser.parse("每15秒深呼吸")
        XCTAssertNotNil(res5)
        XCTAssertEqual(res5?.mode, .interval(minutes: 0, seconds: 15))
        XCTAssertEqual(res5?.cleanedTitle, "深呼吸")
    }
    
    // MARK: - 综合真实自然语言输入测试
    func testComprehensiveRealWorldInputs() {
        let cases = [
            "下午3点开会",
            "下午3点 开会",
            "下午 3 点 开会",
            "今天下午3点开会",
            "明天上午9点开会",
            "明天9点开会",
            "明天9:30 晨会",
            "今天15:00 方案评审",
            "15点开会",
            "15点30开会",
            "3点40开会",
            "3点开会",
            "3点半喝水",
            "下午两点半复盘",
            "两点半开会",
            "30分钟后提醒我喝水",
            "半小时后去吃饭",
            "1小时后关机",
            "每45分钟活动一下",
            "20分钟看书",
            "10分钟",
            "十分钟后",
            "一小时半后",
            "3pm 开会",
            "3:30pm 开会",
            "明天下午3点半 开会",
            "后天上午10点 会议"
        ]
        
        for input in cases {
            let res = parser.parse(input)
            print("TEST CASE [\(input)] -> \(String(describing: res?.mode)) | title: \(res?.cleanedTitle ?? "NIL")")
            XCTAssertNotNil(res, "Failed to parse: \(input)")
        }
    }
}
