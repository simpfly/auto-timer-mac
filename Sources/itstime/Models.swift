import Foundation

public struct ChecklistItem: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var text: String
    public var isCompleted: Bool
    
    public init(id: UUID = UUID(), text: String, isCompleted: Bool = false) {
        self.id = id
        self.text = text
        self.isCompleted = isCompleted
    }
}

public enum PopupContentMode: Codable, Equatable, Hashable {
    case customChecklist(items: [ChecklistItem])     // 待办/日常检查清单
    case todaySystemAgenda                          // 今日日历日程与提醒事项
    case textNotification(message: String)          // 文本提示弹窗
}

public enum TriggerType: Codable, Equatable, Hashable {
    case once(Date)
    case countdown(totalSeconds: Int)       // 倒计时
    case daily(hour: Int, minute: Int)      // 每日固定时刻
    case interval(intervalSeconds: Int)    // 循环间隔
    
    public var displayTitle: String {
        switch self {
        case .once(let date):
            return date.formatted(date: .abbreviated, time: .shortened)
        case .countdown(let secs):
            let m = secs / 60
            let s = secs % 60
            return s == 0 ? "\(m) 分钟" : "\(m)分\(s)秒"
        case .daily(let hour, let minute):
            return String(format: "每天 %02d:%02d", hour, minute)
        case .interval(let secs):
            if secs < 60 {
                return "每 \(secs) 秒"
            }
            let m = secs / 60
            let s = secs % 60
            if m >= 60 && m % 60 == 0 && s == 0 {
                return "每 \(m / 60) 小时"
            }
            if s == 0 {
                return "每 \(m) 分钟"
            }
            return "每 \(m)分\(s)秒"
        }
    }
}

public enum ActionType: Codable, Equatable, Hashable {
    case none                                           // 仅通知提醒
    case popupContent(mode: PopupContentMode)           // 清单 / 今日日程
    case playLocalAudio(
        filePath: String,
        displayName: String,
        loop: Bool,
        volume: Double,
        durationSeconds: Int?
    )
    case openURL(urlString: String)
    
    public var summary: String {
        switch self {
        case .none:
            return "声音通知"
        case .popupContent(let mode):
            switch mode {
            case .textNotification:
                return "文本提示"
            case .customChecklist(let items):
                return "清单 (\(items.count)项)"
            case .todaySystemAgenda:
                return "今日日程"
            }
        case .playLocalAudio(let path, let name, let loop, _, let duration):
            let filename = name.isEmpty ? (path as NSString).lastPathComponent : name
            var desc = filename
            if loop { desc += " (循环)" }
            if let d = duration { desc += " (\(d / 60)分钟)" }
            return desc
        case .openURL(let urlString):
            let clean = urlString.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
            return clean
        }
    }
}

public struct ScheduleTask: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var trigger: TriggerType
    public var action: ActionType
    public var isEnabled: Bool
    public var isPaused: Bool
    public var createdAt: Date
    public var lastTriggeredAt: Date?
    
    public var countdownRemainingSeconds: Int?
    
    public init(
        id: UUID = UUID(),
        name: String,
        trigger: TriggerType,
        action: ActionType = .none,
        isEnabled: Bool = true,
        isPaused: Bool = false,
        createdAt: Date = Date(),
        lastTriggeredAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.action = action
        self.isEnabled = isEnabled
        self.isPaused = isPaused
        self.createdAt = createdAt
        self.lastTriggeredAt = lastTriggeredAt
        
        if case .countdown(let totalSeconds) = trigger {
            self.countdownRemainingSeconds = totalSeconds
        } else {
            self.countdownRemainingSeconds = nil
        }
    }
    
    public func calculateNextTriggerDate(from baseDate: Date = Date()) -> Date? {
        guard isEnabled && !isPaused else { return nil }
        let calendar = Calendar.current
        
        switch trigger {
        case .once(let date):
            return date
        case .countdown(let totalSeconds):
            let remaining = countdownRemainingSeconds ?? totalSeconds
            return baseDate.addingTimeInterval(TimeInterval(remaining))
            
        case .daily(let hour, let minute):
            var comps = calendar.dateComponents([.year, .month, .day], from: baseDate)
            comps.hour = hour
            comps.minute = minute
            comps.second = 0
            guard let targetToday = calendar.date(from: comps) else { return nil }
            if targetToday > baseDate {
                return targetToday
            } else {
                return calendar.date(byAdding: .day, value: 1, to: targetToday)
            }
            
        case .interval(let intervalSeconds):
            let last = lastTriggeredAt ?? createdAt
            let next = last.addingTimeInterval(TimeInterval(intervalSeconds))
            return next > baseDate ? next : baseDate.addingTimeInterval(TimeInterval(intervalSeconds))
        }
    }
    
    public var lastTriggeredDescription: String? {
        guard let date = lastTriggeredAt else { return nil }
        let interval = Int(Date().timeIntervalSince(date))
        if interval < 60 {
            return "刚刚"
        } else if interval < 3600 {
            return "\(interval / 60)分钟前"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd HH:mm"
            return formatter.string(from: date)
        }
    }
    
    public static func sanitizeURLString(_ input: String) -> (url: URL?, formatted: String) {
        var str = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !str.hasPrefix("http://") && !str.hasPrefix("https://") {
            str = "https://" + str
        }
        return (URL(string: str), str)
    }
}
