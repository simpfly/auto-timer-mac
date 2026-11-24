import SwiftUI
import AppKit

struct CalendarSyncSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var eventKit = EventKitService.shared
    @ObservedObject var scheduler = SchedulerEngine.shared
    
    @State private var selectedTab: Int = 0 // 0: 日历日程, 1: 提醒事项待办
    @State private var importedFeedbackText: String? = nil
    
    var body: some View {
        ZStack {
            Color.clear
                .background(.regularMaterial)
                .ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 16) {
                // 顶栏
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 16))
                            .foregroundColor(.accentColor)
                        Text("日历与提醒事项")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    
                    Spacer()
                    
                    Button("关闭") {
                        dismiss()
                        WindowManager.shared.closeCalendarSyncWindow()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .keyboardShortcut(.cancelAction)
                }
                
                if !eventKit.isCalendarAuthorized && !eventKit.isRemindersAuthorized {
                    unauthorizedView
                } else {
                    authorizedContentView
                }
            }
            .padding(22)
        }
        .frame(width: 520, height: 460)
        .onAppear {
            eventKit.checkPermissions()
            if eventKit.isCalendarAuthorized || eventKit.isRemindersAuthorized {
                eventKit.refreshAll()
            }
        }
        .disableFocusEffect()
    }
    
    // MARK: - 未授权引导界面
    private var unauthorizedView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "lock.shield")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(.accentColor)
            
            Text("访问日历与提醒事项")
                .font(.system(size: 16, weight: .semibold))
            
            Text("同步今日日程与待办为定时提醒。")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            Button("授权访问") {
                eventKit.requestAccess()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - 已授权内容界面
    private var authorizedContentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("", selection: $selectedTab) {
                    Text("日历 (\(eventKit.todayCalendarEvents.count))").tag(0)
                    Text("提醒 (\(eventKit.todayReminders.count))").tag(1)
                }
                .pickerStyle(.segmented)
                
                Spacer()
                
                // 一键导入未排日程快捷操作
                if selectedTab == 0 && !unimportedEvents.isEmpty {
                    Button(action: importAllRemainingCalendarEvents) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down.on.square")
                                .font(.system(size: 10))
                            Text("全部导入 (\(unimportedEvents.count))")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            
            if let feedback = importedFeedbackText {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(feedback)
                        .font(.system(size: 12))
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())
            }
            
            ScrollView {
                VStack(spacing: 8) {
                    if selectedTab == 0 {
                        calendarEventsList
                    } else {
                        remindersList
                    }
                }
            }
            .frame(maxHeight: 310)
        }
    }
    
    private var unimportedEvents: [SystemCalendarEvent] {
        eventKit.todayCalendarEvents.filter { ev in
            !ev.isPast && !EventKitService.isCalendarEventImported(event: ev, tasks: scheduler.tasks)
        }
    }
    
    // MARK: - 日历事件列表
    private var calendarEventsList: some View {
        Group {
            if eventKit.todayCalendarEvents.isEmpty {
                emptyListView(message: "暂无今日日程")
            } else {
                ForEach(eventKit.todayCalendarEvents, id: \.id) { ev in
                    let isImported = EventKitService.isCalendarEventImported(event: ev, tasks: scheduler.tasks)
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(ev.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .strikethrough(ev.isPast)
                                    .foregroundColor(ev.isPast ? .secondary : .primary)
                                    .lineLimit(1)
                                
                                if ev.isOngoing {
                                    Text("进行中")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Color.blue.opacity(0.12))
                                        .clipShape(Capsule())
                                } else if ev.isPast {
                                    Text("已结束")
                                        .font(.system(size: 9.5))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Color.secondary.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }
                            
                            HStack(spacing: 6) {
                                Text(ev.formattedTime)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(ev.isPast ? .secondary : (ev.isOngoing ? .blue : .accentColor))
                                
                                if ev.url != nil {
                                    Image(systemName: "link")
                                        .font(.system(size: 9))
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.08))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                        }
                        
                        Spacer()
                        
                        if isImported {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                Text("已在计划中")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                        } else if ev.isPast {
                            Text("已过时")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.6))
                        } else {
                            HStack(spacing: 6) {
                                Button(action: {
                                    prefillCalendarEvent(ev)
                                }) {
                                    Image(systemName: "square.and.pencil")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("填入输入框微调")
                                
                                Button("+ 导入") {
                                    importCalendarEvent(ev)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(10)
                    .glassCard(cornerRadius: 8)
                    .opacity(ev.isPast ? 0.6 : 1.0)
                }
            }
        }
    }
    
    // MARK: - 提醒事项列表
    private var remindersList: some View {
        Group {
            if eventKit.todayReminders.isEmpty {
                emptyListView(message: "暂无未完成事项")
            } else {
                ForEach(eventKit.todayReminders, id: \.id) { rem in
                    let isImported = EventKitService.isReminderImported(reminder: rem, tasks: scheduler.tasks)
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rem.title)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            
                            HStack(spacing: 6) {
                                Text(rem.formattedTime)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(rem.isOverdue ? .orange : (rem.hasSpecificTime ? .accentColor : .secondary))
                                
                                if rem.url != nil {
                                    HStack(spacing: 2) {
                                        Image(systemName: "link")
                                            .font(.system(size: 9))
                                        Text("含链接")
                                            .font(.system(size: 10))
                                    }
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                        }
                        
                        Spacer()
                        
                        if isImported {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                Text("已在计划中")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                        } else {
                            HStack(spacing: 6) {
                                Button(action: {
                                    prefillReminder(rem)
                                }) {
                                    Image(systemName: "square.and.pencil")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("填入输入框微调")
                                
                                Button("+ 导入") {
                                    importReminder(rem)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(10)
                    .padding(10)
                    .glassCard(cornerRadius: 8)
                }
            }
        }
    }
    
    private func emptyListView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .foregroundColor(.secondary.opacity(0.5))
                .font(.system(size: 26))
                .padding(.top, 40)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
    
    // MARK: - 导入与填入逻辑
    private func prefillCalendarEvent(_ ev: SystemCalendarEvent) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: ev.startDate)
        eventKit.prefilledDraft = PrefilledTaskDraft(
            title: ev.title,
            targetURLString: ev.url?.absoluteString,
            targetHour: comps.hour,
            targetMinute: comps.minute,
            suggestedCountdownMinutes: nil,
            isAllDay: ev.isAllDay
        )
        dismiss()
        WindowManager.shared.closeCalendarSyncWindow()
    }
    
    private func prefillReminder(_ rem: SystemReminderTask) {
        let comps = rem.dueDate.map { Calendar.current.dateComponents([.hour, .minute], from: $0) }
        let hour = rem.hasSpecificTime ? comps?.hour : nil
        let minute = rem.hasSpecificTime ? comps?.minute : nil
        
        eventKit.prefilledDraft = PrefilledTaskDraft(
            title: rem.title,
            targetURLString: rem.url?.absoluteString,
            targetHour: hour,
            targetMinute: minute,
            suggestedCountdownMinutes: nil,
            isAllDay: !rem.hasSpecificTime
        )
        dismiss()
        WindowManager.shared.closeCalendarSyncWindow()
    }
    
    private func importCalendarEvent(_ ev: SystemCalendarEvent) {
        let trigger: TriggerType
        let now = Date()
        
        if ev.isAllDay {
            let hour = Calendar.current.component(.hour, from: now)
            let defaultHour = (hour < 9) ? 9 : min(hour + 1, 23)
            trigger = .daily(hour: defaultHour, minute: 0)
        } else if ev.isOngoing {
            trigger = .once(ev.endDate)
        } else if ev.startDate > now {
            trigger = .once(ev.startDate)
        } else {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: ev.startDate)
            trigger = .daily(hour: comps.hour ?? 9, minute: comps.minute ?? 0)
        }
        
        let action: ActionType
        if let url = ev.url {
            action = .openURL(urlString: url.absoluteString)
        } else {
            action = .none
        }
        
        let taskName: String
        if ev.isOngoing {
            taskName = "\(ev.title) (结束)"
        } else {
            taskName = ev.title
        }
        
        let task = ScheduleTask(
            name: taskName,
            trigger: trigger,
            action: action,
            isEnabled: true
        )
        scheduler.addTask(task)
        showFeedback("已导入「\(taskName)」")
    }
    
    private func importAllRemainingCalendarEvents() {
        let targets = unimportedEvents
        guard !targets.isEmpty else { return }
        
        var count = 0
        for ev in targets {
            importCalendarEvent(ev)
            count += 1
        }
        showFeedback("已批量导入 \(count) 项日程")
    }
    
    private func importReminder(_ rem: SystemReminderTask) {
        let trigger: TriggerType
        let now = Date()
        
        if let due = rem.dueDate, rem.hasSpecificTime, !rem.isOverdue {
            trigger = .once(due)
        } else {
            let hour = Calendar.current.component(.hour, from: now)
            let defaultHour = (hour < 9) ? 9 : min(hour + 1, 23)
            trigger = .daily(hour: defaultHour, minute: 0)
        }
        
        let action: ActionType
        if let url = rem.url {
            action = .openURL(urlString: url.absoluteString)
        } else {
            action = .none
        }
        
        let task = ScheduleTask(
            name: rem.title,
            trigger: trigger,
            action: action,
            isEnabled: true
        )
        scheduler.addTask(task)
        showFeedback("已导入「\(rem.title)」")
    }
    
    private func showFeedback(_ text: String) {
        withAnimation {
            self.importedFeedbackText = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                self.importedFeedbackText = nil
            }
        }
    }
}
