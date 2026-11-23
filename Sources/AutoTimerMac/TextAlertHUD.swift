import SwiftUI
import AppKit

@MainActor
public final class TextAlertHUD: ObservableObject {
    public static let shared = TextAlertHUD()
    
    private var alertWindow: NSPanel?
    @Published public var currentTitle: String = ""
    @Published public var currentMessage: String = ""
    
    public init() {}
    
    /// 展示纯文本提醒弹窗卡片（在状态栏图标正下方弹出，必须等待用户确认才关闭）
    public func show(title: String, message: String) {
        self.currentTitle = title.isEmpty ? "定时提醒" : title
        self.currentMessage = message.isEmpty ? "时间已到" : message
        
        if alertWindow == nil {
            createAlertWindow()
        }
        
        guard let window = alertWindow else { return }
        
        // 计算定位：优先放置在状态栏图标正下方，若不可用则定位于屏幕右上角
        updateWindowPosition(window: window)
        
        if !window.isVisible {
            window.alphaValue = 0.0
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                window.animator().alphaValue = 1.0
            }
        } else {
            window.alphaValue = 1.0
            window.orderFrontRegardless()
        }
        
        // 关键要求：绝不自动淡出！完全等待用户点击【我知道了/确认】或右上角【✕】才关闭！
    }
    
    private func updateWindowPosition(window: NSPanel) {
        guard let hosting = window.contentViewController as? NSHostingController<TextAlertBubbleView> else { return }
        
        // 强制重新计算并设定 SwiftUI 真实所需尺寸，杜绝高度测量滞后导致的向上偏移截断
        hosting.view.layoutSubtreeIfNeeded()
        let fittingSize = hosting.sizeThatFits(in: CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude))
        let cardWidth: CGFloat = 300
        let cardHeight: CGFloat = max(115, fittingSize.height)
        
        let screen = StatusItemManager.shared.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let screenRect = screen.visibleFrame
        
        // 状态栏下沿在屏幕坐标系中的 Y 坐标为 screenRect.maxY
        // 窗口顶部距离菜单栏底沿留出 10pt 空隙
        let targetY = screenRect.maxY - cardHeight - 10
        
        // 水平居中于状态栏按钮
        var targetX: CGFloat
        if let statusButton = StatusItemManager.shared.button,
           let btnWindow = statusButton.window {
            let buttonRectInWindow = statusButton.convert(statusButton.bounds, to: nil)
            let buttonRectOnScreen = btnWindow.convertToScreen(buttonRectInWindow)
            targetX = buttonRectOnScreen.midX - cardWidth / 2
        } else {
            targetX = screenRect.maxX - cardWidth - 20
        }
        
        // 边界安全约束：防止超出屏幕左、右、顶
        targetX = max(screenRect.minX + 16, min(targetX, screenRect.maxX - cardWidth - 16))
        let finalY = min(targetY, screenRect.maxY - cardHeight - 8)
        
        window.setFrame(NSRect(x: targetX, y: finalY, width: cardWidth, height: cardHeight), display: true)
    }
    
    /// 用户点击确认或关闭
    public func dismiss() {
        guard let window = alertWindow, window.isVisible else { return }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 0.0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }
    
    private func createAlertWindow() {
        let hosting = NSHostingController(rootView: TextAlertBubbleView())
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 130),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.contentViewController = hosting
        
        self.alertWindow = panel
    }
}

// MARK: - 文本提醒确认气泡卡片（必须等待用户确认才关闭）
struct TextAlertBubbleView: View {
    @ObservedObject var hud = TextAlertHUD.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 顶栏：铃铛图标 + 标签 + 关闭小按钮
            HStack(spacing: 6) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accentColor)
                
                Text("定时提醒")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: {
                    hud.dismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.6))
                        .frame(width: 18, height: 18)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("关闭提醒")
            }
            
            // 任务名称
            Text(hud.currentTitle)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            // 提醒文本内容
            if !hud.currentMessage.isEmpty && hud.currentMessage != hud.currentTitle {
                Text(hud.currentMessage)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // 底部操作区：醒目的【确认 / 我知道了】按钮
            HStack {
                Spacer()
                Button(action: {
                    hud.dismiss()
                }) {
                    Text("我知道了")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        )
    }
}
