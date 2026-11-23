import SwiftUI
import AppKit

struct MainWindowView: View {
    @ObservedObject var scheduler = SchedulerEngine.shared
    @ObservedObject var audioService = AudioService.shared
    
    @State private var showingEditor: Bool = false
    @State private var showingCalendarSync: Bool = false
    @State private var editingTask: ScheduleTask? = nil
    @State private var syncToastMessage: String? = nil
    
    // 正在专注（活跃的倒计时任务）
    private var activeCountdownTasks: [ScheduleTask] {
        scheduler.tasks.filter { task in
            if !task.isEnabled { return false }
            if case .countdown = task.trigger { return true }
            return false
        }
    }
    
    // 计划任务（循环、定时、已停用等；按时间先后顺序放置）
    private var regularPlannedTasks: [ScheduleTask] {
        let now = Date()
        return scheduler.tasks
            .filter { task in
                if case .countdown = task.trigger, task.isEnabled { return false }
                return true
            }
            .sorted { (t1, t2) -> Bool in
                // 1. 启用的排在未启用的前面
                if t1.isEnabled != t2.isEnabled {
                    return t1.isEnabled && !t2.isEnabled
                }
                // 2. 均启用时按最近下一次触发时间从早到晚排序
                let d1 = t1.calculateNextTriggerDate(from: now) ?? Date.distantFuture
                let d2 = t2.calculateNextTriggerDate(from: now) ?? Date.distantFuture
                if d1 != d2 {
                    return d1 < d2
                }
                // 3. 时间相同时按创建时间排序
                return t1.createdAt < t2.createdAt
            }
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // 原生透气毛玻璃背景
            GlassBackgroundView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 顶栏：极简通透
                headerBar
                
                // 任务列表主区域（三级明确视觉层次）
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        // 1. 快捷创建与横向时间带同行并列
                        HStack(alignment: .center) {
                            SectionHeaderView(icon: "bolt.fill", title: "快捷创建", accentColor: .accentColor)
                            Spacer()
                            CompactTimelineStripView()
                                .frame(width: 260)
                        }
                        
                        // 全功能内联创建与编辑（零弹窗）
                        QuickTaskCreateView(editingTask: $editingTask)
                        
                        // 2. 倒计时看板 (若有)
                        if !activeCountdownTasks.isEmpty {
                            SectionHeaderView(icon: "timer", title: "倒计时", count: activeCountdownTasks.count, accentColor: .orange)
                            LazyVStack(spacing: 10) {
                                ForEach(activeCountdownTasks) { task in
                                    taskCard(task, isSpotlight: true)
                                }
                            }
                        }
                        
                        // 3. 计划任务列表
                        if !regularPlannedTasks.isEmpty {
                            SectionHeaderView(icon: "list.bullet.rectangle", title: "计划任务", count: regularPlannedTasks.count, accentColor: .secondary)
                            LazyVStack(spacing: 8) {
                                ForEach(regularPlannedTasks) { task in
                                    taskCard(task, isSpotlight: false)
                                }
                            }
                        } else if activeCountdownTasks.isEmpty && scheduler.tasks.isEmpty {
                            emptyStateView
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            
            // 轻量 Toast 提示
            if let toast = syncToastMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(toast)
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.8))
                .shadow(radius: 8)
                .padding(.top, 12)
                .transition(.opacity)
            }
        }
        .frame(minWidth: 540, minHeight: 500)
        .sheet(isPresented: $showingEditor) {
            TaskEditorSheet(editingTask: editingTask, onSave: { updated in
                if editingTask != nil {
                    scheduler.updateTask(updated)
                } else {
                    scheduler.addTask(updated)
                }
                editingTask = nil
            })
        }
        .sheet(isPresented: $showingCalendarSync) {
            CalendarSyncSheet()
        }
        .disableFocusEffect()
    }
    
    // MARK: - 顶栏
    private var headerBar: some View {
        HStack(alignment: .center) {
            Spacer()
                .frame(width: 70)
            
            Text("任务")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary.opacity(0.85))
            
            Spacer()
            
            if audioService.isPlaying {
                headerPlayingHUD
                    .transition(.opacity)
            }
            
            Spacer()
            
            HStack(spacing: 10) {
                // 日历联动入口
                Button(action: {
                    showingCalendarSync = true
                }) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("日历与提醒事项")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
    
    // MARK: - 单卡片复用构建
    @ViewBuilder
    private func taskCard(_ task: ScheduleTask, isSpotlight: Bool) -> some View {
        TaskCardView(
            task: task,
            isSpotlight: isSpotlight,
            onToggleEnabled: {
                scheduler.toggleTaskEnabled(id: task.id)
            },
            onTogglePause: {
                scheduler.toggleTaskPause(id: task.id)
            },
            onResetCountdown: {
                scheduler.resetCountdown(id: task.id)
            },
            onExecuteNow: {
                scheduler.executeAction(for: task)
            },
            onEdit: {
                editingTask = task
            },
            onDelete: {
                scheduler.deleteTask(byId: task.id)
            },
            onSyncToCalendar: {
                if EventKitService.shared.exportToCalendar(task: task) {
                    showToast("已添加到日历")
                } else {
                    showingCalendarSync = true
                }
            },
            onSyncToReminders: {
                if EventKitService.shared.exportToReminders(task: task) {
                    showToast("已添加到提醒事项")
                } else {
                    showingCalendarSync = true
                }
            }
        )
    }
    
    // MARK: - 顶栏专属轻量播放 HUD (绝不引起页面抖动)
    private var headerPlayingHUD: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .shadow(color: .green.opacity(0.8), radius: 2)
            
            Text(audioService.currentPlayingName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary.opacity(0.85))
                .lineLimit(1)
                .frame(maxWidth: 120)
            
            if !audioService.formattedRemainingTime.isEmpty {
                Text(audioService.formattedRemainingTime)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.green)
            }
            
            Button(action: {
                audioService.stop(fadeOut: true)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("停止")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.12))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.green.opacity(0.3), lineWidth: 0.8)
        )
    }
    
    // MARK: - 空状态视图
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.secondary.opacity(0.45))
                .padding(.top, 50)
            
            Text("无任务")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            
            Button("新建任务") {
                editingTask = nil
                showingEditor = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    private func showToast(_ message: String) {
        withAnimation {
            self.syncToastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                self.syncToastMessage = nil
            }
        }
    }
}

// MARK: - 任务卡片（支持专注特写看板模式与常规计划模式）
struct TaskCardView: View {
    @ObservedObject var audioService = AudioService.shared
    
    let task: ScheduleTask
    var isSpotlight: Bool = false
    let onToggleEnabled: () -> Void
    let onTogglePause: () -> Void
    let onResetCountdown: () -> Void
    let onExecuteNow: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onSyncToCalendar: () -> Void
    let onSyncToReminders: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        if isSpotlight {
            spotlightBody
        } else {
            standardBody
        }
    }
    
    // MARK: - 正在专注特写看板 (Spotlight)
    private var spotlightBody: some View {
        HStack(alignment: .center, spacing: 14) {
            // 左侧：状态指示 + 任务名称 + 动作
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(task.isPaused ? Color.orange : Color.accentColor)
                        .frame(width: 7, height: 7)
                    
                    Text(task.isPaused ? "已暂停" : "正在倒计时")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(task.isPaused ? .orange : .accentColor)
                }
                
                Text(task.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if !actionBriefDescription.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: isActionAudioMissing ? "exclamationmark.triangle.fill" : actionIconName)
                            .font(.system(size: 10))
                            .foregroundColor(isActionAudioMissing ? .red : .secondary)
                        Text(actionBriefDescription)
                            .font(.system(size: 11))
                            .foregroundColor(isActionAudioMissing ? .red : .secondary)
                            .lineLimit(1)
                        
                        if isActionAudioMissing {
                            Text("音频已丢失")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.red)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // 右侧：大号倒计时 + 控制胶囊
            VStack(alignment: .trailing, spacing: 6) {
                if case .countdown(let totalSeconds) = task.trigger {
                    let remaining = task.countdownRemainingSeconds ?? totalSeconds
                    let m = remaining / 60
                    let s = remaining % 60
                    Text(String(format: "%02d:%02d", m, s))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(task.isPaused ? .orange : .accentColor)
                }
                
                HStack(spacing: 6) {
                    Button(action: onTogglePause) {
                        HStack(spacing: 3) {
                            Image(systemName: task.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 9))
                            Text(task.isPaused ? "继续" : "暂停")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(task.isPaused ? .white : .primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(task.isPaused ? Color.orange : Color.primary.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(task.isPaused ? "继续" : "暂停")
                    
                    Button(action: onResetCountdown) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("重置倒计时")
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("删除倒计时")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 12, isSpotlight: true, isPaused: task.isPaused, isEnabled: true)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onEdit() }
        .contextMenu { contextMenuItems }
    }
    
    // MARK: - 常规计划任务卡片 (Standard)
    private var standardBody: some View {
        HStack(alignment: .center, spacing: 12) {
            // 左侧：名称 + 标签 + 核心时间 + 动作
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 6) {
                    Text(task.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(task.isEnabled ? .primary : .secondary.opacity(0.6))
                        .lineLimit(1)
                    
                    triggerBadge
                    
                    // 下次生效时间（图 p1）
                    if let next = nextTriggerTimeString {
                        Text(next)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 6) {
                    timeView
                    
                    if !actionBriefDescription.isEmpty {
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.4))
                        
                        HStack(spacing: 3) {
                            Image(systemName: isActionAudioMissing ? "exclamationmark.triangle.fill" : actionIconName)
                                .font(.system(size: 10))
                                .foregroundColor(isActionAudioMissing ? .red : .secondary)
                            Text(actionBriefDescription)
                                .font(.system(size: 11))
                                .foregroundColor(isActionAudioMissing ? .red : .secondary.opacity(0.8))
                                .lineLimit(1)
                            
                            if isActionAudioMissing {
                                Text("音频已丢失")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.red)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // 右侧：开关 + 低噪微操作工具栏
            VStack(alignment: .trailing, spacing: 6) {
                Toggle("", isOn: Binding(
                    get: { task.isEnabled },
                    set: { _ in onToggleEnabled() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                
                HStack(spacing: 6) {
                    // 播放 / 停止 双态测试按钮（点击变停止，再次点击停止播放）
                    Button(action: handlePlayButtonTapped) {
                        Image(systemName: isPlayingCurrentTaskAudio ? "stop.fill" : "play.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(isPlayingCurrentTaskAudio ? .white : .accentColor)
                            .frame(width: 20, height: 20)
                            .background(isPlayingCurrentTaskAudio ? Color.green : Color.accentColor.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(isPlayingCurrentTaskAudio ? "停止播放" : "测试运行")
                    
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("编辑")
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("删除")
                }
                .opacity(isHovered ? 1.0 : 0.45)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 10, isSpotlight: false, isPaused: task.isPaused, isEnabled: task.isEnabled)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { onEdit() }
        .contextMenu { contextMenuItems }
    }
    
    // MARK: - 右键快捷菜单
    @ViewBuilder
    private var contextMenuItems: some View {
        Button("测试运行") { onExecuteNow() }
        if case .countdown = task.trigger, task.isEnabled {
            Button(task.isPaused ? "继续" : "暂停") { onTogglePause() }
            Button("重置") { onResetCountdown() }
        }
        Divider()
        Button("添加到日历") { onSyncToCalendar() }
        Button("添加到提醒事项") { onSyncToReminders() }
        Divider()
        Button("编辑...") { onEdit() }
        Button("删除", role: .destructive) { onDelete() }
    }
    
    // MARK: - 下次生效时刻计算（图 p1）
    private var nextTriggerTimeString: String? {
        guard task.isEnabled && !task.isPaused else { return nil }
        guard let nextDate = task.calculateNextTriggerDate(from: Date()) else { return nil }
        let calendar = Calendar.current
        let f = DateFormatter()
        if calendar.isDateInToday(nextDate) {
            f.dateFormat = "HH:mm"
            return "下次 " + f.string(from: nextDate)
        } else if calendar.isDateInTomorrow(nextDate) {
            f.dateFormat = "HH:mm"
            return "明天 " + f.string(from: nextDate)
        } else {
            f.dateFormat = "M/d HH:mm"
            return "下次 " + f.string(from: nextDate)
        }
    }
    
    // MARK: - 触发模式徽章
    @ViewBuilder
    private var triggerBadge: some View {
        if !task.isEnabled {
            Text("已停用")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Capsule())
        } else if task.isPaused {
            HStack(spacing: 3) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 7))
                Text("已暂停")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.12))
            .clipShape(Capsule())
        } else {
            switch task.trigger {
            case .once:
                Text("一次").font(.caption).foregroundStyle(.orange)
            case .countdown:
                HStack(spacing: 3) {
                    Image(systemName: "timer")
                        .font(.system(size: 8))
                    Text("倒计时")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Capsule())
                
            case .daily:
                HStack(spacing: 3) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 8))
                    Text("每天")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.indigo)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.indigo.opacity(0.12))
                .clipShape(Capsule())
                
            case .interval:
                HStack(spacing: 3) {
                    Image(systemName: "repeat")
                        .font(.system(size: 8))
                    Text("循环")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.teal)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.teal.opacity(0.12))
                .clipShape(Capsule())
            }
        }
    }
    
    // MARK: - 核心时间展示
    @ViewBuilder
    private var timeView: some View {
        switch task.trigger {
        case .once(let date):
            Text(date.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundColor(task.isEnabled ? .primary : .secondary.opacity(0.6))
                
        case .countdown(let totalSeconds):
            let remaining = task.countdownRemainingSeconds ?? totalSeconds
            let m = remaining / 60
            let s = remaining % 60
            Text(String(format: "%02d:%02d", m, s))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(task.isEnabled ? .primary : .secondary.opacity(0.6))
                .lineLimit(1)
                
        case .daily(let hour, let minute):
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%02d:%02d", hour, minute))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(task.isEnabled ? .primary : .secondary.opacity(0.6))
                Text("每天")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .lineLimit(1)
            
        case .interval(let intervalSeconds):
            if intervalSeconds < 60 {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(intervalSeconds)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(task.isEnabled ? .primary : .secondary.opacity(0.6))
                    Text("秒/次")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .lineLimit(1)
            } else {
                let m = intervalSeconds / 60
                let s = intervalSeconds % 60
                if s == 0 {
                    if m >= 60 && m % 60 == 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(m / 60)")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(task.isEnabled ? .primary : .secondary.opacity(0.6))
                            Text("小时/次")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .lineLimit(1)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(m)")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(task.isEnabled ? .primary : .secondary.opacity(0.6))
                            Text("分钟/次")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .lineLimit(1)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(format: "%02d:%02d", m, s))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(task.isEnabled ? .primary : .secondary.opacity(0.6))
                        Text("分秒/次")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    // 精炼卡片动作描述，去掉重复字眼
    private var actionBriefDescription: String {
        switch task.action {
        case .none:
            return "" // 纯提醒时不重复写“仅定时提醒”，保持极简
        case .popupContent(let mode):
            switch mode {
            case .textNotification: return "文本提示"
            case .customChecklist(let items): return "清单 (\(items.count)项)"
            case .todaySystemAgenda: return "今日日程"
            }
        case .playLocalAudio(let path, let name, _, _, _):
            let filename = name.isEmpty ? (path as NSString).lastPathComponent : name
            return filename
        case .openURL(let urlString):
            let clean = urlString.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
            return clean
        }
    }
    
    private var actionIconName: String {
        switch task.action {
        case .none: return "bell"
        case .popupContent(let mode):
            switch mode {
            case .textNotification: return "text.bubble"
            case .customChecklist: return "checklist"
            case .todaySystemAgenda: return "calendar.day.timeline.left"
            }
        case .playLocalAudio: return "waveform"
        case .openURL: return "safari"
        }
    }
    
    // 检查本地音频文件是否存在或丢失
    private var isActionAudioMissing: Bool {
        if case .playLocalAudio(let path, _, _, _, _) = task.action {
            if path == "内置水滴提示音" { return false }
            return AudioService.resolveAudioURL(for: path) == nil
        }
        return false
    }
    
    // 当前任务的音频动作是否正在播放中
    private var isPlayingCurrentTaskAudio: Bool {
        guard audioService.isPlaying else { return false }
        if case .playLocalAudio(let path, let name, _, _, _) = task.action {
            let audioName = name.isEmpty ? (path as NSString).lastPathComponent : name
            return audioService.currentPlayingName == audioName || audioService.currentPlayingName.contains(audioName)
        }
        return false
    }
    
    // 播放/停止按键处理（点击变停止，再次点击立刻停止播放）
    private func handlePlayButtonTapped() {
        if isPlayingCurrentTaskAudio {
            audioService.stop(fadeOut: false)
        } else {
            onExecuteNow()
        }
    }
}
