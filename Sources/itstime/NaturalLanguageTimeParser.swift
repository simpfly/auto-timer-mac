import Foundation

public struct ParsedTimeResult: Equatable {
    public enum TargetMode: Equatable {
        case countdown(minutes: Int, seconds: Int)
        case daily(hour: Int, minute: Int)
        case interval(minutes: Int, seconds: Int)
    }
    
    public let mode: TargetMode
    public let cleanedTitle: String
    public let matchedText: String
    public let summaryText: String
    
    public init(mode: TargetMode, cleanedTitle: String, matchedText: String, summaryText: String) {
        self.mode = mode
        self.cleanedTitle = cleanedTitle
        self.matchedText = matchedText
        self.summaryText = summaryText
    }
}

public final class NaturalLanguageTimeParser {
    
    public static let shared = NaturalLanguageTimeParser()
    
    public init() {}
    
    /// 解析输入文本，返回识别出的时间模式与净化后的标题
    public func parse(_ text: String) -> ParsedTimeResult? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // 优先级 1: 循环间隔（包含 "每" 或 "每隔"）
        if let intervalResult = parseInterval(trimmed) {
            return intervalResult
        }
        
        // 优先级 2: 每日定时 / 钟点时刻（包含 "每天" 或 "点/分/时段词" 或 "HH:mm"）
        if let dailyResult = parseDailyTime(trimmed) {
            return dailyResult
        }
        
        // 优先级 3: 倒计时 / 相对时长（包含 "分钟"、"秒"、"小时"、"后"、"m"、"s" 等）
        if let countdownResult = parseCountdown(trimmed) {
            return countdownResult
        }
        
        return nil
    }
    
    // MARK: - 1. 循环间隔解析 (Interval)
    private func parseInterval(_ text: String) -> ParsedTimeResult? {
        // 匹配 "每" 或 "每隔" 紧随时间
        // 例: 每30分钟, 每隔1小时, 每半小时, 每45m, 每15秒, 每隔10s
        let pattern = #"(每隔?|循环)\s*([0-9一二两三四五六七八九十半\.]+\s*(?:小时|个半小时|小时半|分钟|分|秒|h|m|s|min|sec)?(?:\s*[0-9一二两三四五六七八九十半\.]+\s*(?:分钟|分|秒|m|s))?)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) else {
            return nil
        }
        
        let fullMatchedString = (text as NSString).substring(with: match.range)
        guard let durationRange = Range(match.range(at: 2), in: text) else { return nil }
        let durationString = String(text[durationRange])
        
        guard let (minutes, seconds) = parseDurationString(durationString), (minutes > 0 || seconds > 0) else {
            return nil
        }
        
        let cleaned = cleanTitle(from: text, matchedRange: match.range)
        let summary: String
        if minutes >= 60 && minutes % 60 == 0 && seconds == 0 {
            summary = "每\(minutes / 60)小时"
        } else if minutes > 0 && seconds > 0 {
            summary = "每\(minutes)分\(seconds)秒"
        } else if minutes > 0 {
            summary = "每\(minutes)分钟"
        } else {
            summary = "每\(seconds)秒"
        }
        
        return ParsedTimeResult(
            mode: .interval(minutes: minutes, seconds: seconds),
            cleanedTitle: cleaned,
            matchedText: fullMatchedString,
            summaryText: summary
        )
    }
    
    // MARK: - 2. 每日定时时刻解析 (Daily)
    private func parseDailyTime(_ text: String) -> ParsedTimeResult? {
        // 先检查是否有日期修饰词: 今天/今日/明天/明早/明日/后天/每天/每日
        // A. 匹配 HH:mm 格式 (例如 9:30, 09:30, 15:45, 18:00, 3:30pm, 10:00am)
        let colonPattern = #"(每天|每日|今天|今日|明天|明早|明日|后天)?\s*(清晨|早晨|早上|上午|中午|下午|傍晚|晚上|夜里|今晚|凌晨)?\s*([0-2]?[0-9])\s*[:：]\s*([0-5][0-9])\s*(am|pm)?"#
        if let regex = try? NSRegularExpression(pattern: colonPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) {
            
            let fullMatchedString = (text as NSString).substring(with: match.range)
            var hour = 0
            var minute = 0
            
            var periodModifier: String? = nil
            if match.range(at: 2).location != NSNotFound, let r = Range(match.range(at: 2), in: text) {
                periodModifier = String(text[r])
            }
            if let hrRange = Range(match.range(at: 3), in: text), let h = Int(text[hrRange]) {
                hour = h
            }
            if let minRange = Range(match.range(at: 4), in: text), let m = Int(text[minRange]) {
                minute = m
            }
            
            var ampm: String? = nil
            if match.range(at: 5).location != NSNotFound, let r = Range(match.range(at: 5), in: text) {
                ampm = String(text[r]).lowercased()
            }
            
            if let p = ampm {
                hour = adjustHourForPeriod(hour: hour, period: p)
            } else if let period = periodModifier {
                hour = adjustHourForPeriod(hour: hour, period: period)
            } else {
                hour = inferAmbiguousHour(hour: hour)
            }
            
            if hour >= 0 && hour < 24 && minute >= 0 && minute < 60 {
                let cleaned = cleanTitle(from: text, matchedRange: match.range)
                let timeStr = String(format: "%02d:%02d", hour, minute)
                return ParsedTimeResult(
                    mode: .daily(hour: hour, minute: minute),
                    cleanedTitle: cleaned,
                    matchedText: fullMatchedString,
                    summaryText: "每天 \(timeStr)"
                )
            }
        }
        
        // B. 匹配英文简写时间 (如 3pm, 11am, 3:30pm)
        let englishPattern = #"(每天|每日|今天|今日|明天|明早|明日|后天)?\s*([0-1]?[0-9])\s*(am|pm)"#
        if let regex = try? NSRegularExpression(pattern: englishPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) {
            
            let fullMatchedString = (text as NSString).substring(with: match.range)
            var hour = 0
            if let hrRange = Range(match.range(at: 2), in: text), let h = Int(text[hrRange]) {
                hour = h
            }
            if let ampmRange = Range(match.range(at: 3), in: text) {
                let ampm = String(text[ampmRange]).lowercased()
                hour = adjustHourForPeriod(hour: hour, period: ampm)
            }
            
            if hour >= 0 && hour < 24 {
                let cleaned = cleanTitle(from: text, matchedRange: match.range)
                let timeStr = String(format: "%02d:00", hour)
                return ParsedTimeResult(
                    mode: .daily(hour: hour, minute: 0),
                    cleanedTitle: cleaned,
                    matchedText: fullMatchedString,
                    summaryText: "每天 \(timeStr)"
                )
            }
        }
        
        // C. 匹配中文日常时刻 (如 下午3点半, 晚上8点, 上午9点20分, 10点半, 每天8点, 3点开会, 两点半)
        let chineseTimePattern = #"(每天|每日|今天|今日|明天|明早|明日|后天)?\s*(清晨|早晨|早上|上午|中午|下午|傍晚|晚上|夜里|今晚|凌晨)?\s*([0-9一二两三四五六七八九十]+)\s*(?:点|时)\s*(?:([0-9一二两三四五六七八九十]+)\s*分?|半|一刻|三刻)?"#
        if let regex = try? NSRegularExpression(pattern: chineseTimePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) {
            
            let fullMatchedString = (text as NSString).substring(with: match.range)
            
            let hasDailyOrDate = match.range(at: 1).location != NSNotFound
            let hasPeriod = match.range(at: 2).location != NSNotFound
            
            // 只要出现点/时或有时段/日期修饰
            if hasDailyOrDate || hasPeriod || fullMatchedString.contains("点") || fullMatchedString.contains("时") {
                var periodModifier: String? = nil
                if hasPeriod, let r = Range(match.range(at: 2), in: text) {
                    periodModifier = String(text[r])
                }
                
                var rawHour = 0
                if let hrRange = Range(match.range(at: 3), in: text) {
                    let hrStr = String(text[hrRange])
                    rawHour = parseNumber(hrStr) ?? -1
                }
                
                var minute = 0
                if match.range(at: 4).location != NSNotFound, let minRange = Range(match.range(at: 4), in: text) {
                    let minStr = String(text[minRange])
                    minute = parseNumber(minStr) ?? 0
                } else if fullMatchedString.contains("半") {
                    minute = 30
                } else if fullMatchedString.contains("一刻") {
                    minute = 15
                } else if fullMatchedString.contains("三刻") {
                    minute = 45
                }
                
                if rawHour >= 0 && rawHour <= 24 {
                    var hour = rawHour
                    if let period = periodModifier {
                        hour = adjustHourForPeriod(hour: hour, period: period)
                    } else {
                        // 无上下午时段词时，做常识性推断（1..6 点推断为下午）
                        hour = inferAmbiguousHour(hour: hour)
                    }
                    if hour == 24 { hour = 0 }
                    
                    if hour >= 0 && hour < 24 && minute >= 0 && minute < 60 {
                        let cleaned = cleanTitle(from: text, matchedRange: match.range)
                        let timeStr = String(format: "%02d:%02d", hour, minute)
                        return ParsedTimeResult(
                            mode: .daily(hour: hour, minute: minute),
                            cleanedTitle: cleaned,
                            matchedText: fullMatchedString,
                            summaryText: timeStr
                        )
                    }
                }
            }
        }
        
        return nil
    }
    
    // MARK: - 3. 倒计时解析 (Countdown)
    private func parseCountdown(_ text: String) -> ParsedTimeResult? {
        // 支持：
        // 25分钟后, 25分钟, 1小时30分钟, 半小时后, 1个半小时, 30s后, 45秒, 10m, 1h
        // 前缀或后缀允许出现: "倒计时", "后", "提醒我"
        let pattern = #"(?:倒计时)?\s*([0-9一二两三四五六七八九十半\.]+\s*(?:个半小时|小时半|小时|分钟|分|秒|h|m|s|min|sec))(?:\s*([0-9一二两三四五六七八九十半\.]+\s*(?:分钟|分|秒|m|s)))?\s*(?:后|提醒我)?"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        for match in matches {
            let fullMatchedString = (text as NSString).substring(with: match.range)
            
            // 确保不是空匹配
            let trimmedMatch = fullMatchedString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedMatch.isEmpty else { continue }
            
            // 必须包含有效的时间单位，防止误判
            let hasValidUnit = ["小时", "分", "秒", "h", "m", "s", "min", "sec", "半"].contains {
                trimmedMatch.lowercased().contains($0)
            }
            guard hasValidUnit else { continue }
            
            guard let (minutes, seconds) = parseDurationString(trimmedMatch), (minutes > 0 || seconds > 0) else {
                continue
            }
            
            let cleaned = cleanTitle(from: text, matchedRange: match.range)
            let summary: String
            if minutes >= 60 && minutes % 60 == 0 && seconds == 0 {
                summary = "\(minutes / 60)小时"
            } else if minutes > 0 && seconds > 0 {
                summary = "\(minutes)分\(seconds)秒"
            } else if minutes > 0 {
                summary = "\(minutes)分钟"
            } else {
                summary = "\(seconds)秒"
            }
            
            return ParsedTimeResult(
                mode: .countdown(minutes: minutes, seconds: seconds),
                cleanedTitle: cleaned,
                matchedText: fullMatchedString,
                summaryText: summary
            )
        }
        
        return nil
    }
    
    // MARK: - 辅助方法：解析持续时长 (返回分与秒)
    private func parseDurationString(_ rawString: String) -> (minutes: Int, seconds: Int)? {
        let str = rawString.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        var totalSeconds = 0
        
        // 特殊处理 "半小时" / "半个钟" / "半个钟头" / "一小时半"
        if str.contains("半小时") || str.contains("半个钟") || str.contains("小时半") {
            if str.contains("1个半小时") || str.contains("一个半小时") || str.contains("1小时半") || str.contains("一小时半") {
                return (90, 0)
            }
            if str.contains("2个半小时") || str.contains("两个半小时") || str.contains("2小时半") || str.contains("两小时半") {
                return (150, 0)
            }
            return (30, 0)
        }
        
        // 匹配小时 (X小时 / Xh)
        let hrRegex = try? NSRegularExpression(pattern: #"([0-9一二两三四五六七八九十\.]+)\s*(?:个?小时|h)"#, options: .caseInsensitive)
        if let match = hrRegex?.firstMatch(in: str, options: [], range: NSRange(location: 0, length: str.utf16.count)),
           let r = Range(match.range(at: 1), in: str) {
            let numStr = String(str[r])
            if let val = Double(numStr) {
                totalSeconds += Int(val * 3600)
            } else if let num = parseNumber(numStr) {
                totalSeconds += num * 3600
            }
        }
        
        // 匹配分钟 (X分钟 / X分 / Xm / Xmin)
        let minRegex = try? NSRegularExpression(pattern: #"([0-9一二两三四五六七八九十\.]+)\s*(?:分钟|分|min|m)(?!s)"#, options: .caseInsensitive)
        if let match = minRegex?.firstMatch(in: str, options: [], range: NSRange(location: 0, length: str.utf16.count)),
           let r = Range(match.range(at: 1), in: str) {
            let numStr = String(str[r])
            if let val = Double(numStr) {
                totalSeconds += Int(val * 60)
            } else if let num = parseNumber(numStr) {
                totalSeconds += num * 60
            }
        }
        
        // 匹配秒 (X秒 / Xs / Xsec)
        let secRegex = try? NSRegularExpression(pattern: #"([0-9一二两三四五六七八九十\.]+)\s*(?:秒钟|秒|sec|s)"#, options: .caseInsensitive)
        if let match = secRegex?.firstMatch(in: str, options: [], range: NSRange(location: 0, length: str.utf16.count)),
           let r = Range(match.range(at: 1), in: str) {
            let numStr = String(str[r])
            if let val = Double(numStr) {
                totalSeconds += Int(val)
            } else if let num = parseNumber(numStr) {
                totalSeconds += num
            }
        }
        
        if totalSeconds > 0 {
            let m = totalSeconds / 60
            let s = totalSeconds % 60
            return (m, s)
        }
        
        return nil
    }
    
    // MARK: - 辅助方法：中文与阿拉伯数字解析
    private func parseNumber(_ text: String) -> Int? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let intVal = Int(clean) {
            return intVal
        }
        
        // 中文数字转换 (1-99)
        let dict: [Character: Int] = [
            "零": 0, "一": 1, "二": 2, "两": 2, "三": 3,
            "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
        ]
        
        if clean == "十" { return 10 }
        if clean.count == 2 {
            if clean.hasPrefix("十") {
                let second = clean.suffix(1).first!
                return 10 + (dict[second] ?? 0)
            } else if clean.hasSuffix("十") {
                let first = clean.prefix(1).first!
                return (dict[first] ?? 1) * 10
            }
        } else if clean.count == 3 && clean.contains("十") {
            let chars = Array(clean)
            let tens = dict[chars[0]] ?? 1
            let ones = dict[chars[2]] ?? 0
            return tens * 10 + ones
        } else if clean.count == 1, let v = dict[clean.first!] {
            return v
        }
        
        return nil
    }
    
    // MARK: - 辅助方法：时段调整 (上下午/晚上/am/pm)
    private func adjustHourForPeriod(hour: Int, period: String) -> Int {
        var h = hour
        let p = period.lowercased()
        if p.contains("下午") || p.contains("晚上") || p.contains("傍晚") || p.contains("夜里") || p.contains("今晚") || p == "pm" {
            if h < 12 {
                h += 12
            }
        } else if p.contains("中午") {
            if h < 11 {
                h += 12
            }
        } else if p.contains("清晨") || p.contains("早晨") || p.contains("早上") || p.contains("上午") || p.contains("明早") || p == "am" {
            if h == 12 {
                h = 0
            }
        } else if p.contains("凌晨") {
            if h == 12 {
                h = 0
            }
        }
        return h
    }
    
    /// 当用户未指定上下午时段词时，按人类作息常识智能推断（1..6 点常识推断为下午）
    private func inferAmbiguousHour(hour: Int) -> Int {
        if hour >= 1 && hour <= 6 {
            return hour + 12
        }
        return hour
    }
    
    // MARK: - 辅助方法：清洗标题
    private func cleanTitle(from originalText: String, matchedRange: NSRange) -> String {
        guard let r = Range(matchedRange, in: originalText) else { return originalText }
        var result = originalText
        result.removeSubrange(r)
        
        // 剔除常见的关联前缀后缀，例如 "今天"、"明天"、"后天"、"后"、"提醒我"、"去"、"准备" 等连词
        var cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripKeywords = [
            "今天", "今日", "明天", "明日", "明早", "后天", "每天", "每日",
            "后", "提醒我", "提醒", "记得", "开始", "到期", "准时"
        ]
        
        var changed = true
        while changed {
            changed = false
            for kw in stripKeywords {
                if cleaned.hasPrefix(kw) {
                    cleaned = String(cleaned.dropFirst(kw.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    changed = true
                }
                if cleaned.hasSuffix(kw) {
                    cleaned = String(cleaned.dropLast(kw.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    changed = true
                }
            }
        }
        
        // 去除多余标点与空白
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " ,，、:：-—"))
        return cleaned
    }
}
