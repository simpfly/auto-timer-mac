import SwiftUI
import AppKit

struct MainWindowView: View {
    @ObservedObject var scheduler = SchedulerEngine.shared
    @ObservedObject var audioService = AudioService.shared
    @ObservedObject var updateManager = UpdateManager.shared
    
    @State private var showingCalendarSync: Bool = false
    @State private var editingTask: ScheduleTask? = nil
    @State private var syncToastMessage: String? = nil
    @State private var currentPage: MainWindowPage = .tasks
    
    enum MainWindowPage {
        case tasks
        case screenTime
    }
    
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
                // 方案 B：按最近下一次触发时间从早到晚排序，开关切换时不重排移位
                let d1 = t1.calculateNextTriggerDate(from: now) ?? Date.distantFuture
                let d2 = t2.calculateNextTriggerDate(from: now) ?? Date.distantFuture
                if d1 != d2 {
                    return d1 < d2
                }
                // 时间相同时按创建时间排序
                return t1.createdAt < t2.createdAt
            }
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // 原生清亮毛玻璃背景（避免 underWindowBackground 沉闷发灰）
            GlassBackgroundView(material: .popover, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            if currentPage == .screenTime {
                ScreenTimeView(onDismiss: {
                    currentPage = .tasks
                })
                .padding(.top, 8)
                .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    // 顶栏：极简通透（位于红绿灯下方，与主内容区左对齐）
                    headerBar
                    
                    // 任务列表主区域（三级明确视觉层次）
                    ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        // 1. 快捷创建面板（提醒类型选择器替代静态标题，与时间流动轴同行）
                        QuickTaskCreateView(editingTask: $editingTask, timelineWidth: 260)
                        
                        // 2. 倒计时看板 (若有)
                        if !activeCountdownTasks.isEmpty {
                            SectionHeaderView(icon: "timer", title: "倒计时", count: activeCountdownTasks.count, accentColor: .orange)
                            LazyVStack(spacing: 10) {
                                ForEach(activeCountdownTasks) { task in
                                    taskCard(task, isSpotlight: true)
                                }
                            }
                        }
                        
                        // 3. 屏幕时间与事件概览（置于计划上方，与菜单栏布局一致）
                        ScreenTimeSummaryCard {
                            currentPage = .screenTime
                        }
                        
                        // 4. 计划任务列表
                        if !regularPlannedTasks.isEmpty {
                            SectionHeaderView(icon: "list.bullet.rectangle", title: "计划", count: regularPlannedTasks.count, accentColor: .secondary)
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
        .sheet(isPresented: $showingCalendarSync) {
            CalendarSyncSheet()
        }
        .disableFocusEffect()
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ItsTime_ShowScreenTimePage"))) { _ in
            currentPage = .screenTime
        }
    }
    
    // MARK: - 顶栏 (位于红绿灯下方，左对齐内容区 + 中间 HUD 绝对居中层叠)
    private var headerBar: some View {
        HStack(alignment: .center) {
            // 左侧：品牌标题与下方内容左对齐
            BrandTitleView()
                .fixedSize()
            
            Spacer()
            
            // 右侧：更多功能菜单（与菜单栏功能完全一致）
            Menu {
                SharedMoreMenuContent(
                    showOpenMainWindow: false,
                    onOpenScreenTime: { currentPage = .screenTime },
                    onOpenCalendarSync: { showingCalendarSync = true }
                )
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.8))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .focusable(false)
        }
        .frame(height: 28)
        .overlay(
            Group {
                if audioService.isPlaying {
                    headerPlayingHUD
                        .transition(.opacity.animation(.easeInOut(duration: 0.16)))
                }
            },
            alignment: .center
        )
        .padding(.horizontal, 24)
        .padding(.top, 4)
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
                scheduler.executeAction(for: task, isManualTest: true)
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
            .floatingTooltip("停止")
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
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
                WindowManager.shared.openNewReminder()
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

// MARK: - 紧凑型短款绿色开关组件
struct CompactGreenSwitch: View {
    let isOn: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Color(nsColor: .systemGreen) : Color.secondary.opacity(0.2))
                    .frame(width: 32, height: 18)
                
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .padding(.horizontal, 2)
                    .shadow(color: Color.black.opacity(0.18), radius: 1, x: 0, y: 0.5)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.16), value: isOn)
        .accessibilityLabel(isOn ? "已启用" : "已停用")
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
        let semanticColor: Color = task.isPaused ? .orange : .accentColor
        let progressRatio: CGFloat = {
            guard case .countdown(let totalSeconds) = task.trigger, totalSeconds > 0 else { return 0 }
            let remaining = task.countdownRemainingSeconds ?? totalSeconds
            return max(0, min(1, CGFloat(remaining) / CGFloat(totalSeconds)))
        }()
        
        return HStack(alignment: .center, spacing: 14) {
            // 左侧：状态指示 + 任务名称 + 动作
            VStack(alignment: .leading, spacing: 5) {
                if task.isPaused {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                        Text("已暂停")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.orange)
                    }
                }
                
                Text(task.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
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
                        .foregroundColor(task.isPaused ? .orange : .primary)
                }
                
                HStack(spacing: 6) {
                    Button(action: onTogglePause) {
                        Image(systemName: task.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(task.isPaused ? .white : .primary)
                            .frame(width: 22, height: 22)
                            .background(task.isPaused ? Color.orange : Color.primary.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .floatingTooltip(task.isPaused ? "继续" : "暂停")
                    
                    Button(action: onResetCountdown) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .floatingTooltip("重置倒计时")
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .floatingTooltip("删除倒计时")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            // 底部极细静态进度线
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                    Rectangle()
                        .fill(semanticColor.opacity(0.8))
                        .frame(width: geo.size.width * progressRatio)
                }
            }
            .frame(height: 2.5)
        }
        .glassCard(cornerRadius: 12, isSpotlight: true, isPaused: task.isPaused, isEnabled: true)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onEdit() }
        .contextMenu { contextMenuItems }
    }
    
    // MARK: - 常规计划任务卡片 (Standard)
    private var standardBody: some View {
        let showActionButtons = isHovered || isPlayingCurrentTaskAudio
        
        return HStack(alignment: .center, spacing: 12) {
            // 左侧：极简两行排版（名称 + 提示类型图标 + 异常状态；触发图标 + 时间 + 下次触发）
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 6) {
                    if !actionBriefDescription.isEmpty || task.action == .none {
                        Image(systemName: isActionAudioMissing ? "exclamationmark.triangle.fill" : actionIconName)
                            .font(.system(size: 10.5))
                            .foregroundColor(isActionAudioMissing ? .red : .secondary.opacity(0.75))
                            .floatingTooltip(isActionAudioMissing ? "音频已丢失：\(actionBriefDescription)" : (actionBriefDescription.isEmpty ? "声音通知" : actionBriefDescription))
                    }
                    
                    Text(task.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(task.isEnabled ? .primary : .secondary.opacity(0.6))
                        .lineLimit(1)
                    
                    statusBadge
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Image(systemName: triggerIconName)
                            .font(.system(size: 10))
                            .foregroundColor(task.isEnabled ? .secondary : .secondary.opacity(0.5))
                            .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 1.5 }
                        timeView
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .layoutPriority(1)
                    
                    if let next = nextTriggerTimeString {
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text(next)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // 右侧：悬停操作按钮（仅悬停或正在播放时显示） + 开关
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Button(action: handlePlayButtonTapped) {
                        Image(systemName: isPlayingCurrentTaskAudio ? "stop.fill" : "play.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(isPlayingCurrentTaskAudio ? .white : .accentColor)
                            .frame(width: 20, height: 20)
                            .background(isPlayingCurrentTaskAudio ? Color.green : Color.accentColor.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .floatingTooltip(isPlayingCurrentTaskAudio ? "停止播放" : "测试运行")
                    
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .floatingTooltip("编辑")
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .floatingTooltip("删除")
                }
                .opacity(showActionButtons ? 1.0 : 0.0)
                .allowsHitTesting(showActionButtons)
                .animation(.easeInOut(duration: 0.14), value: showActionButtons)
                
                CompactGreenSwitch(
                    isOn: task.isEnabled,
                    onToggle: onToggleEnabled
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 10, isSpotlight: false, isPaused: task.isPaused, isEnabled: task.isEnabled, isHovered: isHovered)
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
    
    // MARK: - 异常状态徽章（仅停用或暂停时显示，正常启用态保持极简零冗余）
    @ViewBuilder
    private var statusBadge: some View {
        if !task.isEnabled {
            Text("已停用")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.75))
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
        }
    }
    
    // MARK: - 触发类型轻量图标（替代彩色胶囊）
    private var triggerIconName: String {
        switch task.trigger {
        case .once: return "calendar"
        case .countdown: return "timer"
        case .daily: return "clock"
        case .interval: return "repeat"
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
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(task.isEnabled ? .primary : .secondary.opacity(0.6))
                .lineLimit(1)
                
        case .daily(let hour, let minute):
            Text(String(format: "%02d:%02d", hour, minute))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(task.isEnabled ? .primary : .secondary.opacity(0.6))
                .lineLimit(1)
            
        case .interval(let intervalSeconds):
            if intervalSeconds < 60 {
                Text("\(intervalSeconds)秒")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(task.isEnabled ? .primary : .secondary.opacity(0.6))
                    .lineLimit(1)
            } else {
                let m = intervalSeconds / 60
                let s = intervalSeconds % 60
                if s == 0 {
                    if m >= 60 && m % 60 == 0 {
                        Text("\(m / 60)小时")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(task.isEnabled ? .primary : .secondary.opacity(0.6))
                            .lineLimit(1)
                    } else {
                        Text("\(m)分钟")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(task.isEnabled ? .primary : .secondary.opacity(0.6))
                            .lineLimit(1)
                    }
                } else {
                    Text(String(format: "%02d:%02d", m, s))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(task.isEnabled ? .primary : .secondary.opacity(0.6))
                        .lineLimit(1)
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
