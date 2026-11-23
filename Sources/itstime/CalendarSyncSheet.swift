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
            
            Text("读取今日日程与待办，快速转为定时；到点可打开会议链接或弹窗提醒。")
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
            Picker("", selection: $selectedTab) {
                Text("日历日程 (\(eventKit.todayCalendarEvents.count))").tag(0)
                Text("提醒事项 (\(eventKit.todayReminders.count))").tag(1)
            }
            .pickerStyle(.segmented)
            
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
    
    // MARK: - 日历事件列表
    private var calendarEventsList: some View {
        Group {
            if eventKit.todayCalendarEvents.isEmpty {
                emptyListView(message: "暂无日程")
            } else {
                ForEach(eventKit.todayCalendarEvents, id: \.id) { ev in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ev.title)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            
                            HStack(spacing: 6) {
                                Text(ev.formattedTime)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.accentColor)
                                
                                if ev.url != nil {
                                    Text("· 含会议链接")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        Button("+ 导入") {
                            importCalendarEvent(ev)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(10)
                    .glassCard(cornerRadius: 8)
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
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rem.title)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            
                            Text(rem.formattedTime)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("+ 导入") {
                            importReminder(rem)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
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
    
    // MARK: - 导入逻辑
    private func importCalendarEvent(_ ev: SystemCalendarEvent) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: ev.startDate)
        let trigger = TriggerType.daily(hour: comps.hour ?? 9, minute: comps.minute ?? 0)
        
        let action: ActionType
        if let url = ev.url {
            action = .openURL(urlString: url.absoluteString)
        } else {
            action = .none // 纯定时提醒
        }
        
        let task = ScheduleTask(
            name: ev.title,
            trigger: trigger,
            action: action,
            isEnabled: true
        )
        scheduler.addTask(task)
        
        showFeedback("已导入「\(ev.title)」")
    }
    
    private func importReminder(_ rem: SystemReminderTask) {
        let trigger: TriggerType
        if let d = rem.dueDate {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: d)
            trigger = .daily(hour: comps.hour ?? 9, minute: comps.minute ?? 0)
        } else {
            trigger = .countdown(totalSeconds: 30 * 60)
        }
        
        let task = ScheduleTask(
            name: rem.title,
            trigger: trigger,
            action: .none,
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
