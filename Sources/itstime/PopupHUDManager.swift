import AppKit
import SwiftUI

@MainActor
public final class PopupHUDManager: ObservableObject {
    public static let shared = PopupHUDManager()
    
    private var hudWindow: NSPanel?
    
    @Published public var currentTask: ScheduleTask? = nil
    @Published public var currentMode: PopupContentMode = .todaySystemAgenda
    @Published public var checklistItems: [ChecklistItem] = []
    
    public init() {}
    
    /// 触发弹出纯文本提示大字卡片（不受勿扰模式阻断）
    public func showTextAlert(for task: ScheduleTask) {
        show(for: task, mode: .textNotification(message: task.name))
    }
    
    /// 触发弹出 Checklist 或日程看板
    public func show(for task: ScheduleTask, mode: PopupContentMode) {
        self.currentTask = task
        self.currentMode = mode
        
        switch mode {
        case .textNotification:
            break
        case .customChecklist(let items):
            self.checklistItems = items.isEmpty ? [
                ChecklistItem(text: "检查当天工作目标"),
                ChecklistItem(text: "喝一杯温水"),
                ChecklistItem(text: "站立活动或深呼吸")
            ] : items
        case .todaySystemAgenda:
            EventKitService.shared.refreshAll()
        }
        
        if hudWindow == nil {
            createHUDWindow()
        }
        
        guard let window = hudWindow else { return }
        
        // 居中屏幕偏上展开，纯净平滑淡入（零过冲、零回弹弹跳）
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenRect = screen.visibleFrame
        let targetX = screenRect.midX - window.frame.width / 2
        let targetY = screenRect.midY - window.frame.height / 2 + 50
        let targetFrame = NSRect(x: targetX, y: targetY, width: window.frame.width, height: window.frame.height)
        
        let initialFrame = NSRect(x: targetX, y: targetY + 4, width: window.frame.width, height: window.frame.height)
        
        window.setFrame(initialFrame, display: false)
        window.alphaValue = 0.0
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // 单阶段平滑微滑入与淡入 (0.16s，纯净确定性动效)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
            window.animator().setFrame(targetFrame, display: true)
        }
    }
    
    public func close() {
        guard let window = hudWindow else { return }
        let exitFrame = NSRect(
            x: window.frame.origin.x,
            y: window.frame.origin.y + 4,
            width: window.frame.width,
            height: window.frame.height
        )
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0.0
            window.animator().setFrame(exitFrame, display: true)
        }, completionHandler: {
            window.orderOut(nil)
        })
    }
    
    public func toggleItem(id: UUID) {
        if let idx = checklistItems.firstIndex(where: { $0.id == id }) {
            checklistItems[idx].isCompleted.toggle()
            
            // 同步回任务状态
            if var task = currentTask {
                task.action = .popupContent(mode: .customChecklist(items: checklistItems))
                SchedulerEngine.shared.updateTask(task)
            }
        }
    }
    
    private func createHUDWindow() {
        let hosting = NSHostingController(rootView: PopupHUDContentView())
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.borderless, .nonactivatingPanel], // 纯无边框，彻底避免系统红绿灯外露
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating // 置顶浮动
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentViewController = hosting
        panel.isMovableByWindowBackground = true
        
        self.hudWindow = panel
    }
}

// MARK: - HUD 弹窗内容视图 (纯粹原生毛玻璃，无任何外露红绿灯)
struct PopupHUDContentView: View {
    @ObservedObject var manager = PopupHUDManager.shared
    @ObservedObject var eventKit = EventKitService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 顶栏：标题与纯净关闭按钮
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: iconName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.accentColor)
                    
                    Text(displayTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                }
                .fixedSize()
                
                Spacer()
                
                Button(action: {
                    manager.close()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            
            Divider().opacity(0.25)
            
            // 核心内容区 (保证最小与最大高度，绝不塌陷)
            VStack(alignment: .leading, spacing: 8) {
                switch manager.currentMode {
                case .textNotification(let msg):
                    textNotificationSection(message: msg)
                case .customChecklist:
                    checklistSection
                case .todaySystemAgenda:
                    agendaSection
                }
            }
            .frame(minHeight: isTextMode ? 90 : 150)
            
            Divider().opacity(0.25)
            
            // 底部操作栏
            HStack {
                if isTextMode {
                    Text("定时提醒已到达")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                } else if case .customChecklist = manager.currentMode {
                    let completed = manager.checklistItems.filter { $0.isCompleted }.count
                    Text("已完成 \(completed) / \(manager.checklistItems.count) 项")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                } else {
                    Text("今日日程与待办")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(isTextMode ? "我知道了" : "完成") {
                    manager.close()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.white.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.25), radius: 30, x: 0, y: 15)
        .disableFocusEffect()
    }
    
    private var displayTitle: String {
        if let name = manager.currentTask?.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return "清单"
    }
    
    // Checklist 打卡视图
    private var checklistSection: some View {
        VStack(spacing: 8) {
            ForEach(manager.checklistItems) { item in
                HStack(spacing: 12) {
                    Button(action: {
                        manager.toggleItem(id: item.id)
                    }) {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundColor(item.isCompleted ? .green : .secondary.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    
                    Text(item.text)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(item.isCompleted ? .secondary : .primary)
                        .strikethrough(item.isCompleted, color: .secondary.opacity(0.6))
                    
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(item.isCompleted ? Color.green.opacity(0.08) : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(item.isCompleted ? Color.green.opacity(0.2) : Color.white.opacity(0.1), lineWidth: 0.8)
                )
            }
        }
    }
    
    // 今日日程看板视图
    private var agendaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("日历日程")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            
            if eventKit.todayCalendarEvents.isEmpty {
                Text("今日无待办日程")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.vertical, 8)
            } else {
                ForEach(eventKit.todayCalendarEvents.prefix(4), id: \.id) { ev in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ev.title)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            Text(ev.formattedTime)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.accentColor)
                        }
                        Spacer()
                        if let url = ev.url {
                            Button("进入") {
                                NSWorkspace.shared.open(url)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(10)
                    .glassPanel(cornerRadius: 8)
                }
            }
            
            if !eventKit.todayReminders.isEmpty {
                Text("提醒事项")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                
                ForEach(eventKit.todayReminders.prefix(3), id: \.id) { rem in
                    HStack {
                        Image(systemName: "circle")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(rem.title)
                            .font(.system(size: 13))
                            .lineLimit(1)
                        Spacer()
                        Text(rem.formattedTime)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .glassPanel(cornerRadius: 8)
                }
            }
        }
    }
    
    private var isTextMode: Bool {
        if case .textNotification = manager.currentMode { return true }
        return false
    }
    
    private func textNotificationSection(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message.isEmpty ? (manager.currentTask?.name ?? "时间已到！") : message)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
            
            HStack(spacing: 6) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
                Text("到达设定时间，请注意查看与安排")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
    
    private var iconName: String {
        switch manager.currentMode {
        case .textNotification: return "text.bubble.fill"
        case .customChecklist: return "checklist"
        case .todaySystemAgenda: return "calendar.day.timeline.left"
        }
    }
}
