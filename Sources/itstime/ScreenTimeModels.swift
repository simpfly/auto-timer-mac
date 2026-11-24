import Foundation
import AppKit

/// 统计时间维度
public enum TimeScope: String, CaseIterable, Identifiable {
    case day = "日"
    case week = "周"
    case month = "月"
    case year = "年"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .day: return "今日"
        case .week: return "本周"
        case .month: return "本月"
        case .year: return "本年"
        }
    }
}

/// 单个应用的使用记录
public struct AppUsageRecord: Identifiable, Codable, Equatable {
    public var id: String { bundleIdentifier }
    public let bundleIdentifier: String
    public var appName: String
    public var durationSeconds: TimeInterval
    /// 激活/切换至前台的次数
    public var activationCount: Int
    public var lastActiveDate: Date
    
    public init(
        bundleIdentifier: String,
        appName: String,
        durationSeconds: TimeInterval = 0,
        activationCount: Int = 1,
        lastActiveDate: Date = Date()
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.durationSeconds = durationSeconds
        self.activationCount = activationCount
        self.lastActiveDate = lastActiveDate
    }
    
    /// 人类易读的时长文本（如 "1小时25分" 或 "4分钟"）
    public var formattedDuration: String {
        let total = Int(durationSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        
        if hours > 0 {
            return "\(hours)小时\(minutes)分"
        } else if minutes > 0 {
            return "\(minutes)分钟"
        } else {
            return "\(max(1, seconds))秒"
        }
    }
}

/// 定时事件/自动化任务的触发统计
public struct EventTriggerRecord: Identifiable, Codable, Equatable {
    public var id: UUID
    public var taskName: String
    public var triggerTypeTitle: String
    public var count: Int
    public var lastTriggeredAt: Date
    
    public init(
        id: UUID,
        taskName: String,
        triggerTypeTitle: String,
        count: Int = 1,
        lastTriggeredAt: Date = Date()
    ) {
        self.id = id
        self.taskName = taskName
        self.triggerTypeTitle = triggerTypeTitle
        self.count = count
        self.lastTriggeredAt = lastTriggeredAt
    }
}

/// 单次历史事件触发日志（用于在时间带展现已发生事件）
public struct PastEventLogItem: Identifiable, Codable, Equatable {
    public var id: UUID
    public var taskId: UUID?
    public var taskName: String
    public var triggerTypeTitle: String
    public var timestamp: Date
    public var kindString: String // countdown, daily, interval, once, calendar
    public var actionDesc: String
    
    public init(
        id: UUID = UUID(),
        taskId: UUID? = nil,
        taskName: String,
        triggerTypeTitle: String,
        timestamp: Date = Date(),
        kindString: String = "once",
        actionDesc: String = ""
    ) {
        self.id = id
        self.taskId = taskId
        self.taskName = taskName
        self.triggerTypeTitle = triggerTypeTitle
        self.timestamp = timestamp
        self.kindString = kindString
        self.actionDesc = actionDesc
    }
}

/// 某一日期的屏幕时间与事件统计完整记录
public struct DailyScreenTimeRecord: Codable, Equatable {
    public let dateString: String // 格式: yyyy-MM-dd
    public var totalActiveSeconds: TimeInterval
    public var appUsages: [String: AppUsageRecord] // Key 为 bundleIdentifier
    public var eventTriggers: [UUID: EventTriggerRecord] // Key 为 Task UUID
    public var pastEventLogs: [PastEventLogItem]? // 触发历史流水日志
    
    public init(
        dateString: String,
        totalActiveSeconds: TimeInterval = 0,
        appUsages: [String: AppUsageRecord] = [:],
        eventTriggers: [UUID: EventTriggerRecord] = [:],
        pastEventLogs: [PastEventLogItem] = []
    ) {
        self.dateString = dateString
        self.totalActiveSeconds = totalActiveSeconds
        self.appUsages = appUsages
        self.eventTriggers = eventTriggers
        self.pastEventLogs = pastEventLogs
    }
    
    /// 按使用时长倒序排列的应用记录列表
    public var sortedApps: [AppUsageRecord] {
        appUsages.values.sorted { $0.durationSeconds > $1.durationSeconds }
    }
    
    /// 按触发次数倒序排列的事件列表
    public var sortedEventTriggers: [EventTriggerRecord] {
        eventTriggers.values.sorted { $0.count > $1.count }
    }
    
    /// 今日所有事件累计触发的总次数
    public var totalEventTriggerCount: Int {
        eventTriggers.values.reduce(0) { $0 + $1.count }
    }
    
    /// 人类易读的总时长
    public var formattedTotalDuration: String {
        let total = Int(totalActiveSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        
        if hours > 0 {
            return "\(hours)小时\(minutes)分"
        } else if minutes > 0 {
            return "\(minutes)分钟"
        } else {
            return "\(total)秒"
        }
    }
}

/// 某个时间跨度（日/周/月/年）聚合统计结果
public struct AggregatedScreenTimeStats: Equatable {
    public var scope: TimeScope
    public var totalActiveSeconds: TimeInterval
    public var sortedApps: [AppUsageRecord]
    public var sortedEventTriggers: [EventTriggerRecord]
    public var totalEventTriggerCount: Int
    public var periodDescription: String
    public var dailyAverageSeconds: TimeInterval
    public var pastEventLogs: [PastEventLogItem]
    
    public init(
        scope: TimeScope,
        totalActiveSeconds: TimeInterval = 0,
        sortedApps: [AppUsageRecord] = [],
        sortedEventTriggers: [EventTriggerRecord] = [],
        totalEventTriggerCount: Int = 0,
        periodDescription: String = "",
        dailyAverageSeconds: TimeInterval = 0,
        pastEventLogs: [PastEventLogItem] = []
    ) {
        self.scope = scope
        self.totalActiveSeconds = totalActiveSeconds
        self.sortedApps = sortedApps
        self.sortedEventTriggers = sortedEventTriggers
        self.totalEventTriggerCount = totalEventTriggerCount
        self.periodDescription = periodDescription
        self.dailyAverageSeconds = dailyAverageSeconds
        self.pastEventLogs = pastEventLogs
    }
    
    public var formattedTotalDuration: String {
        let total = Int(totalActiveSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    public var formattedDailyAverage: String {
        let total = Int(dailyAverageSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
