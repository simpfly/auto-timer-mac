import SwiftUI
import AppKit

// MARK: - 原生 NSVisualEffectView 封装 (macOS 原生磨砂毛玻璃背景)
public struct GlassBackgroundView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material = .underWindowBackground
    public var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    public var state: NSVisualEffectView.State = .active
    
    public init(
        material: NSVisualEffectView.Material = .underWindowBackground,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }
    
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.state = state
        return visualEffectView
    }
    
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = .withinWindow
        nsView.state = state
    }
}

// MARK: - SwiftUI 原生 Glass 修饰符
public struct GlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat = 12
    public var isSpotlight: Bool = false
    public var isPaused: Bool = false
    public var isEnabled: Bool = true
    
    public func body(content: Content) -> some View {
        content
            .background(
                isSpotlight
                    ? (isPaused ? Color.orange.opacity(0.06) : Color.accentColor.opacity(0.05))
                    : Color(NSColor.controlBackgroundColor).opacity(0.5)
            )
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        isSpotlight
                            ? (isPaused ? Color.orange.opacity(0.22) : Color.primary.opacity(0.09))
                            : Color.primary.opacity(isEnabled ? 0.08 : 0.04),
                        lineWidth: 0.8
                    )
            )
            .shadow(
                color: isSpotlight ? Color.black.opacity(0.05) : Color.black.opacity(0.03),
                radius: isSpotlight ? 6 : 3,
                x: 0,
                y: isSpotlight ? 2 : 1.5
            )
    }
}

public extension View {
    func glassCard(cornerRadius: CGFloat = 12, isSpotlight: Bool = false, isPaused: Bool = false, isEnabled: Bool = true) -> some View {
        self.modifier(GlassCardModifier(cornerRadius: cornerRadius, isSpotlight: isSpotlight, isPaused: isPaused, isEnabled: isEnabled))
    }
    
    // 兼容历史调用
    func glassCard(cornerRadius: CGFloat = 12, isHighlighted: Bool, isPaused: Bool = false) -> some View {
        self.modifier(GlassCardModifier(cornerRadius: cornerRadius, isSpotlight: isHighlighted, isPaused: isPaused, isEnabled: true))
    }
    
    func glassPanel(cornerRadius: CGFloat = 10) -> some View {
        self
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
            )
    }
    
    /// 统一桌面提醒浮窗 HUD 容器规范（毛玻璃材质、渐变描边、柔和投影）
    func glassHUD(cornerRadius: CGFloat = 16, accentColor: Color? = nil) -> some View {
        self
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                (accentColor ?? Color.white).opacity(accentColor != nil ? 0.32 : 0.28),
                                Color.primary.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.9
                    )
            )
            .shadow(color: Color.black.opacity(0.18), radius: 20, x: 0, y: 10)
    }
    
    /// 轻量即时毛玻璃悬浮提示（替代系统原生延迟 .help）
    func floatingTooltip(_ text: String) -> some View {
        self.modifier(FloatingTooltipModifier(text: text))
    }
    
    /// 全局禁用 SwiftUI 焦点框及动效
    @ViewBuilder
    func disableFocusEffect() -> some View {
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled()
        } else {
            self
        }
    }
}

// MARK: - 轻量即时毛玻璃悬浮提示控制器（独立无焦点浮层，不被 ScrollView 裁切）
@MainActor
private final class FloatingTooltipController {
    static let shared = FloatingTooltipController()
    
    private var panel: NSPanel?
    private var showWorkItem: DispatchWorkItem?
    private var activeId: UUID?
    
    func scheduleShow(id: UUID, text: String, delay: TimeInterval = 0.65) {
        guard !text.isEmpty else { return }
        showWorkItem?.cancel()
        activeId = id
        
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.activeId == id else { return }
            self.present(text: text)
        }
        showWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
    
    func hide(id: UUID) {
        guard activeId == id else { return }
        showWorkItem?.cancel()
        showWorkItem = nil
        activeId = nil
        panel?.orderOut(nil)
    }
    
    private func present(text: String) {
        let contentView = TooltipBubbleContent(text: text)
        let hosting = NSHostingView(rootView: contentView)
        hosting.layoutSubtreeIfNeeded()
        let fittingSize = hosting.fittingSize
        
        let panel = self.panel ?? {
            let p = NSPanel(
                contentRect: NSRect(origin: .zero, size: fittingSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.level = .popUpMenu
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .transient]
            self.panel = p
            return p
        }()
        
        panel.contentView = hosting
        
        // 定位在鼠标指针上方居中（若靠近屏幕顶部则自动翻折到下方）
        let mouse = NSEvent.mouseLocation
        let screenFrame = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        
        var x = mouse.x - fittingSize.width / 2
        x = max(screenFrame.minX + 8, min(x, screenFrame.maxX - fittingSize.width - 8))
        
        var y = mouse.y + 18
        if y + fittingSize.height > screenFrame.maxY - 6 {
            y = mouse.y - fittingSize.height - 14
        }
        
        panel.setFrame(NSRect(x: x, y: y, width: fittingSize.width, height: fittingSize.height), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }
}

private struct TooltipBubbleContent: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.primary)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.75)
            )
            .shadow(color: Color.black.opacity(0.14), radius: 8, x: 0, y: 3)
            .padding(6) // 给阴影留出渲染空间，避免被浮窗边缘裁切
    }
}

private struct FloatingTooltipModifier: ViewModifier {
    let text: String
    @State private var tooltipId = UUID()
    
    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering {
                    FloatingTooltipController.shared.scheduleShow(id: tooltipId, text: text)
                } else {
                    FloatingTooltipController.shared.hide(id: tooltipId)
                }
            }
            .onDisappear {
                FloatingTooltipController.shared.hide(id: tooltipId)
            }
    }
}
