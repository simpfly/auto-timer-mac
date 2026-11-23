import SwiftUI
import AppKit

// MARK: - 菜单栏直接展开主面板（纯菜单栏常驻，无需独立窗口）
struct MenuBarView: View {
    @ObservedObject var scheduler = SchedulerEngine.shared
    @ObservedObject var audioService = AudioService.shared
    @ObservedObject var launchManager = LaunchAtLoginManager.shared
    
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
            VStack(spacing: 0) {
                // 1. 顶栏：极简通透
                headerBar
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                
                Divider()
                    .opacity(0.25)
                
                // 2. 主区域（三级明确视觉层次）
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        // Section 1: 快捷创建与时间流动轴同行并列
                        HStack(alignment: .center) {
                            SectionHeaderView(icon: "bolt.fill", title: "快捷创建", accentColor: .accentColor)
                            Spacer()
                            CompactTimelineStripView()
                                .frame(width: 200)
                        }
                        
                        // 全功能内联创建与编辑（零弹窗）
                        QuickTaskCreateView(editingTask: $editingTask)
                        
                        // Section 2: 倒计时特写看板 (若存在进行中的倒计时)
                        if !activeCountdownTasks.isEmpty {
                            SectionHeaderView(icon: "timer", title: "倒计时", count: activeCountdownTasks.count, accentColor: .orange)
                            LazyVStack(spacing: 10) {
                                ForEach(activeCountdownTasks) { task in
                                    taskCard(task, isSpotlight: true)
                                }
                            }
                        }
                        
                        // Section 3: 计划任务列表
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
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 18)
                }
            }
            
            // 轻量 Toast 提示
            if let toast = syncToastMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(toast)
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.8))
                .shadow(radius: 6)
                .padding(.top, 10)
                .transition(.opacity)
            }
        }
        .frame(width: 380, height: 540)
        .background(.regularMaterial)
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
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.accentColor)
                
                Text("AutoTimer")
                    .font(.system(size: 14, weight: .bold))
                
                let activeCount = scheduler.tasks.filter { $0.isEnabled }.count
                if activeCount > 0 {
                    Text("\(activeCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            
            Spacer()
            
            // 中间：若正在试听/播放音频，静默嵌入顶栏正中微 HUD 胶囊（绝不引起下方卡片弹跳！）
            if audioService.isPlaying {
                headerPlayingHUD
                    .transition(.opacity)
            }
            
            Spacer()
            
            // 更多功能菜单（收拢主窗口、日历与提醒、运行控制、设置与退出，和右键菜单保持一致）
            Menu {
                // 1. 窗口与功能
                Button {
                    WindowManager.shared.openMainWindow()
                } label: {
                    Label("打开主窗口", systemImage: "macwindow")
                }
                
                Button {
                    showingCalendarSync = true
                } label: {
                    Label("日历与提醒事项", systemImage: "calendar.badge.clock")
                }
                
                Divider()
                
                // 2. 运行控制
                let hasActive = scheduler.hasActiveRunningTasks
                Button {
                    scheduler.togglePauseAll()
                } label: {
                    Label(
                        hasActive ? "暂停所有任务" : "恢复所有任务",
                        systemImage: hasActive ? "pause.circle" : "play.circle"
                    )
                }
                
                if audioService.isPlaying {
                    Button {
                        audioService.stop(fadeOut: true)
                    } label: {
                        Label("停止播放: \(audioService.currentPlayingName)", systemImage: "stop.circle.fill")
                    }
                }
                
                Divider()
                
                // 3. 偏好与系统
                Toggle(isOn: Binding(
                    get: { launchManager.isEnabled },
                    set: { _ in launchManager.toggle() }
                )) {
                    Label("开机自启动", systemImage: "power.circle")
                }
                
                Button {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            NSApplication.AboutPanelOptionKey.applicationName: "AutoTimer",
                            NSApplication.AboutPanelOptionKey.version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                        ]
                    )
                } label: {
                    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                    Label("关于 AutoTimer (v\(appVersion))", systemImage: "info.circle")
                }
                
                Divider()
                
                // 4. 退出
                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("退出 AutoTimer", systemImage: "power")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .focusable(false)
            .help("更多功能与设置")
        }
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
    
    // MARK: - 顶栏专属轻量播放 HUD (绝不挤压页面引起抖动/弹跳)
    private var headerPlayingHUD: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .shadow(color: .green.opacity(0.8), radius: 2)
            
            Text(audioService.currentPlayingName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.primary.opacity(0.85))
                .lineLimit(1)
                .frame(maxWidth: 80)
            
            if !audioService.formattedRemainingTime.isEmpty {
                Text(audioService.formattedRemainingTime)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
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
            .help("停止试听/播放")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Color.green.opacity(0.12))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.green.opacity(0.3), lineWidth: 0.8)
        )
    }
    
    // MARK: - 空状态
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.secondary.opacity(0.4))
                .padding(.top, 24)
            
            Text("暂无任务")
                .font(.system(size: 13, weight: .medium))
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
        .padding(.vertical, 20)
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
