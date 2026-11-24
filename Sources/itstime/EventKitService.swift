import Foundation
import EventKit
import Combine

public struct SystemCalendarEvent: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let url: URL?
    public let location: String?
    public let isAllDay: Bool
    
    public var isPast: Bool {
        endDate < Date()
    }
    
    public var isOngoing: Bool {
        let now = Date()
        return startDate <= now && endDate > now
    }
    
    public var isUpcoming: Bool {
        startDate > Date()
    }
    
    public var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        if isAllDay {
            return "全天"
        }
        return "\(f.string(from: startDate)) - \(f.string(from: endDate))"
    }
}

public struct SystemReminderTask: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let dueDate: Date?
    public let hasSpecificTime: Bool
    public let url: URL?
    public let priority: Int
    
    public init(
        id: String,
        title: String,
        dueDate: Date?,
        hasSpecificTime: Bool,
        url: URL? = nil,
        priority: Int = 0
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.hasSpecificTime = hasSpecificTime
        self.url = url
        self.priority = priority
    }
    
    public var isOverdue: Bool {
        guard let d = dueDate, hasSpecificTime else { return false }
        return d < Date()
    }
    
    public var formattedTime: String {
        guard let d = dueDate else { return "无具体时间" }
        if !hasSpecificTime {
            if Calendar.current.isDateInToday(d) {
                return "今天 (全天)"
            } else if Calendar.current.isDateInTomorrow(d) {
                return "明天 (全天)"
            } else {
                let f = DateFormatter()
                f.dateFormat = "MM-dd"
                return "\(f.string(from: d)) (全天)"
            }
        }
        
        let f = DateFormatter()
        if Calendar.current.isDateInToday(d) {
            f.dateFormat = "今天 HH:mm"
        } else if Calendar.current.isDateInTomorrow(d) {
            f.dateFormat = "明天 HH:mm"
        } else {
            f.dateFormat = "MM-dd HH:mm"
        }
        var str = f.string(from: d)
        if isOverdue {
            str += " (已逾期)"
        }
        return str
    }
}

public struct PrefilledTaskDraft: Equatable {
    public let title: String
    public let targetURLString: String?
    public let targetHour: Int?
    public let targetMinute: Int?
    public let suggestedCountdownMinutes: Int?
    public let isAllDay: Bool
    
    public init(
        title: String,
        targetURLString: String? = nil,
        targetHour: Int? = nil,
        targetMinute: Int? = nil,
        suggestedCountdownMinutes: Int? = nil,
        isAllDay: Bool = false
    ) {
        self.title = title
        self.targetURLString = targetURLString
        self.targetHour = targetHour
        self.targetMinute = targetMinute
        self.suggestedCountdownMinutes = suggestedCountdownMinutes
        self.isAllDay = isAllDay
    }
}

public enum EventKitSearchResult: Identifiable, Hashable {
    case calendar(event: SystemCalendarEvent)
    case reminder(task: SystemReminderTask)
    
    public var id: String {
        switch self {
        case .calendar(let ev): return "cal_\(ev.id)"
        case .reminder(let rm): return "rem_\(rm.id)"
        }
    }
    
    public var title: String {
        switch self {
        case .calendar(let ev): return ev.title
        case .reminder(let rm): return rm.title
        }
    }
    
    public var subtitle: String {
        switch self {
        case .calendar(let ev):
            if ev.isAllDay {
                var text = "日程 · 今天全天"
                if ev.url != nil { text += " · 包含链接" }
                return text
            }
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            var text = "日程 · 今天 \(f.string(from: ev.startDate))"
            if ev.url != nil { text += " · 包含链接" }
            return text
        case .reminder(let rm):
            var text = "待办 · \(rm.formattedTime)"
            if rm.url != nil { text += " · 包含链接" }
            return text
        }
    }
    
    public var suggestedHourMinute: (hour: Int, minute: Int)? {
        switch self {
        case .calendar(let ev):
            if ev.isAllDay { return nil }
            let comps = Calendar.current.dateComponents([.hour, .minute], from: ev.startDate)
            if let h = comps.hour, let m = comps.minute {
                return (h, m)
            }
            return nil
        case .reminder(let rm):
            guard let due = rm.dueDate, rm.hasSpecificTime else { return nil }
            let comps = Calendar.current.dateComponents([.hour, .minute], from: due)
            if let h = comps.hour, let m = comps.minute {
                return (h, m)
            }
            return nil
        }
    }
    
    public var targetDate: Date? {
        switch self {
        case .calendar(let ev): return ev.startDate
        case .reminder(let rm): return rm.dueDate
        }
    }
    
    public var url: URL? {
        switch self {
        case .calendar(let ev): return ev.url
        case .reminder(let rm): return rm.url
        }
    }
    
    public var iconName: String {
        switch self {
        case .calendar: return "calendar"
        case .reminder: return "checklist"
        }
    }
}

@MainActor
public final class EventKitService: ObservableObject {
    public static let shared = EventKitService()
    
    private let eventStore = EKEventStore()
    
    @Published public private(set) var isCalendarAuthorized: Bool = false
    @Published public private(set) var isRemindersAuthorized: Bool = false
    
    @Published public private(set) var todayCalendarEvents: [SystemCalendarEvent] = []
    @Published public private(set) var todayReminders: [SystemReminderTask] = []
    
    /// 用于向快速创建输入框直填的待办草稿（标题及自动匹配的链接）
    @Published public var prefilledDraft: PrefilledTaskDraft? = nil
    
    public init() {
        checkPermissions()
    }
    
    public func checkPermissions() {
        let eventStatus = EKEventStore.authorizationStatus(for: .event)
        let reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
        
        self.isCalendarAuthorized = (eventStatus == .authorized) || (eventStatus.rawValue == 4 /* fullAccess in macOS 14 */)
        self.isRemindersAuthorized = (reminderStatus == .authorized) || (reminderStatus.rawValue == 4)
        
        if self.isCalendarAuthorized || self.isRemindersAuthorized {
            self.refreshAll()
        }
    }
    
    /// 模糊搜索已授权的日历日程与提醒待办
    public func search(query: String) -> [EventKitSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        var results: [EventKitSearchResult] = []
        
        if isCalendarAuthorized {
            for ev in todayCalendarEvents {
                if ev.title.localizedCaseInsensitiveContains(trimmed) {
                    results.append(.calendar(event: ev))
                }
            }
        }
        
        if isRemindersAuthorized {
            for rm in todayReminders {
                if rm.title.localizedCaseInsensitiveContains(trimmed) {
                    results.append(.reminder(task: rm))
                }
            }
        }
        
        // 最多展示 5 条，避免界面拥挤
        return Array(results.prefix(5))
    }
    
    /// 请求系统日历与提醒事项授权
    public func requestAccess(completion: (() -> Void)? = nil) {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { [weak self] granted, _ in
                Task { @MainActor in
                    self?.isCalendarAuthorized = granted
                    self?.eventStore.requestFullAccessToReminders { [weak self] grantedReminders, _ in
                        Task { @MainActor in
                            self?.isRemindersAuthorized = grantedReminders
                            self?.refreshAll()
                            completion?()
                        }
                    }
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] granted, _ in
                Task { @MainActor in
                    self?.isCalendarAuthorized = granted
                    self?.eventStore.requestAccess(to: .reminder) { [weak self] grantedReminders, _ in
                        Task { @MainActor in
                            self?.isRemindersAuthorized = grantedReminders
                            self?.refreshAll()
                            completion?()
                        }
                    }
                }
            }
        }
    }
    
    /// 刷新日历与提醒事项数据
    public func refreshAll() {
        fetchCalendarEvents()
        fetchReminders()
    }
    
    /// 智能检测与提取文本中的首个有效 http/https 链接
    nonisolated public static func extractURL(
        primaryURL: URL?,
        notes: String?,
        location: String? = nil,
        title: String? = nil
    ) -> URL? {
        if let primary = primaryURL {
            return primary
        }
        
        let candidates = [notes, location, title].compactMap { $0 }.filter { !$0.isEmpty }
        guard !candidates.isEmpty else { return nil }
        
        let combined = candidates.joined(separator: "\n")
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        
        let matches = detector.matches(
            in: combined,
            options: [],
            range: NSRange(location: 0, length: (combined as NSString).length)
        )
        for match in matches {
            if let url = match.url, url.scheme == "http" || url.scheme == "https" {
                return url
            }
        }
        return nil
    }
    
    /// 获取今日全天至未来 24 小时的日历事件（包含进行中与全天日程）
    public func fetchCalendarEvents() {
        guard isCalendarAuthorized else { return }
        
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let ekEvents = eventStore.events(matching: predicate)
        
        self.todayCalendarEvents = ekEvents.map { ev in
            let detectedURL = EventKitService.extractURL(
                primaryURL: ev.url,
                notes: ev.notes,
                location: ev.location,
                title: ev.title
            )
            return SystemCalendarEvent(
                id: ev.eventIdentifier ?? UUID().uuidString,
                title: ev.title ?? "未命名日程",
                startDate: ev.startDate,
                endDate: ev.endDate,
                url: detectedURL,
                location: ev.location,
                isAllDay: ev.isAllDay
            )
        }.sorted { $0.startDate < $1.startDate }
    }
    
    // MARK: - 导入状态与去重辅助判断
    
    /// 判断某个系统日历日程是否已被导入为定时任务
    nonisolated public static func isCalendarEventImported(
        event: SystemCalendarEvent,
        tasks: [ScheduleTask]
    ) -> Bool {
        let cleanTitle = event.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanTitle.isEmpty else { return false }
        
        let evComps = Calendar.current.dateComponents([.hour, .minute], from: event.startDate)
        
        return tasks.contains { task in
            let taskCleanName = task.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard taskCleanName == cleanTitle || taskCleanName.contains(cleanTitle) || cleanTitle.contains(taskCleanName) else {
                return false
            }
            
            // 全天日程比对名称
            if event.isAllDay {
                return true
            }
            
            // 进一步比对触发时间
            switch task.trigger {
            case .once(let date):
                let tComps = Calendar.current.dateComponents([.hour, .minute], from: date)
                return tComps.hour == evComps.hour && tComps.minute == evComps.minute
            case .daily(let h, let m):
                return h == evComps.hour && m == evComps.minute
            default:
                return true
            }
        }
    }
    
    /// 判断某个提醒事项待办是否已被导入为定时任务
    nonisolated public static func isReminderImported(
        reminder: SystemReminderTask,
        tasks: [ScheduleTask]
    ) -> Bool {
        let cleanTitle = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanTitle.isEmpty else { return false }
        
        return tasks.contains { task in
            let taskCleanName = task.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return taskCleanName == cleanTitle || taskCleanName.contains(cleanTitle) || cleanTitle.contains(taskCleanName)
        }
    }
    
    /// 获取近期的待办提醒事项
    public func fetchReminders() {
        guard isRemindersAuthorized else { return }
        
        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
            guard let reminders = reminders else { return }
            
            let list = reminders.compactMap { r -> SystemReminderTask? in
                let comps = r.dueDateComponents
                let dueDate = comps?.date
                let hasSpecificTime = (comps?.hour != nil)
                let detectedURL = EventKitService.extractURL(
                    primaryURL: r.url,
                    notes: r.notes,
                    title: r.title
                )
                return SystemReminderTask(
                    id: r.calendarItemIdentifier,
                    title: r.title ?? "未命名提醒",
                    dueDate: dueDate,
                    hasSpecificTime: hasSpecificTime,
                    url: detectedURL,
                    priority: r.priority
                )
            }.sorted { ($0.dueDate ?? Date.distantFuture) < ($1.dueDate ?? Date.distantFuture) }
            
            Task { @MainActor in
                self?.todayReminders = list
            }
        }
    }
    
    /// 将 It's Time 定时任务同步到系统日历
    public func exportToCalendar(task: ScheduleTask) -> Bool {
        guard isCalendarAuthorized else { return false }
        guard let targetDate = task.calculateNextTriggerDate() else { return false }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = "【It's Time】\(task.name)"
        event.startDate = targetDate
        event.endDate = targetDate.addingTimeInterval(1800) // 默认 30 分钟
        event.calendar = eventStore.defaultCalendarForNewEvents
        
        if case .openURL(let urlString) = task.action, let url = URL(string: urlString) {
            event.url = url
        }
        
        do {
            try eventStore.save(event, span: .thisEvent)
            return true
        } catch {
            print("❌ 保存到系统日历失败: \(error)")
            return false
        }
    }
    
    /// 将 It's Time 定时任务同步到系统提醒事项
    public func exportToReminders(task: ScheduleTask) -> Bool {
        guard isRemindersAuthorized else { return false }
        guard let targetDate = task.calculateNextTriggerDate() else { return false }
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = "【It's Time】\(task.name)"
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: targetDate)
        
        if case .openURL(let urlString) = task.action, let url = URL(string: urlString) {
            reminder.url = url
        }
        
        do {
            try eventStore.save(reminder, commit: true)
            return true
        } catch {
            print("❌ 保存到系统提醒事项失败: \(error)")
            return false
        }
    }
}
