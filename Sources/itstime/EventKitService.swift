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
    
    public var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: startDate)
    }
}

public struct SystemReminderTask: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let dueDate: Date?
    public let priority: Int
    
    public var formattedTime: String {
        guard let d = dueDate else { return "无具体时间" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
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
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return "日程 · 今天 \(f.string(from: ev.startDate))"
        case .reminder(let rm):
            if let due = rm.dueDate {
                let f = DateFormatter()
                f.dateFormat = "HH:mm"
                return "待办 · \(f.string(from: due))"
            }
            return "提醒事项 · 未定时间"
        }
    }
    
    public var targetDate: Date? {
        switch self {
        case .calendar(let ev): return ev.startDate
        case .reminder(let rm): return rm.dueDate
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
    
    /// 获取从当前起到未来 24 小时内的日历事件
    public func fetchCalendarEvents() {
        guard isCalendarAuthorized else { return }
        
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let ekEvents = eventStore.events(matching: predicate)
        
        self.todayCalendarEvents = ekEvents.map { ev in
            SystemCalendarEvent(
                id: ev.eventIdentifier ?? UUID().uuidString,
                title: ev.title ?? "未命名日程",
                startDate: ev.startDate,
                endDate: ev.endDate,
                url: ev.url,
                location: ev.location,
                isAllDay: ev.isAllDay
            )
        }.sorted { $0.startDate < $1.startDate }
    }
    
    /// 获取近期的待办提醒事项
    public func fetchReminders() {
        guard isRemindersAuthorized else { return }
        
        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
            guard let reminders = reminders else { return }
            
            let list = reminders.compactMap { r -> SystemReminderTask? in
                let dueDate = r.dueDateComponents?.date
                return SystemReminderTask(
                    id: r.calendarItemIdentifier,
                    title: r.title ?? "未命名提醒",
                    dueDate: dueDate,
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
        
        do {
            try eventStore.save(reminder, commit: true)
            return true
        } catch {
            print("❌ 保存到系统提醒事项失败: \(error)")
            return false
        }
    }
}
