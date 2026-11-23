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
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = state
        return visualEffectView
    }
    
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
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
                    ? (isPaused ? Color.orange.opacity(0.08) : Color.accentColor.opacity(0.08))
                    : Color(NSColor.controlBackgroundColor).opacity(0.35)
            )
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        isSpotlight
                            ? (isPaused ? Color.orange.opacity(0.55) : Color.accentColor.opacity(0.55))
                            : Color.white.opacity(isEnabled ? 0.14 : 0.06),
                        lineWidth: isSpotlight ? 1.2 : 0.8
                    )
            )
            .shadow(
                color: isSpotlight ? (isPaused ? Color.orange.opacity(0.12) : Color.accentColor.opacity(0.12)) : Color.black.opacity(0.03),
                radius: isSpotlight ? 8 : 4,
                x: 0,
                y: isSpotlight ? 3 : 2
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
