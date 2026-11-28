import SwiftUI
import AppKit

@MainActor
public final class TextAlertHUD: ObservableObject {
    public static let shared = TextAlertHUD()
    fileprivate static let cardWidth: CGFloat = 296
    fileprivate static let cornerRadius: CGFloat = 16
    
    private struct QueuedAlert {
        let title: String
        let message: String
        let color: Color
        let onConfirm: () -> Void
        let onIgnore: () -> Void
    }
    private var queuedAlerts: [QueuedAlert] = []
    private var currentConfirmation: (() -> Void)?
    private var currentIgnoreAction: (() -> Void)?
    private var isDismissing = false
    private var alertWindow: NSPanel?
    @Published public var currentTitle: String = ""
    @Published public var currentMessage: String = ""
    @Published public var currentColor: Color = .accentColor
    
    public init() {}
    
    /// 展示纯文本提醒弹窗卡片（在状态栏图标正下方微弹弹出，必须等待用户确认或忽略才关闭）
    public func show(
        title: String,
        message: String,
        color: Color = .accentColor,
        onConfirm: @escaping () -> Void = {},
        onIgnore: @escaping () -> Void = {}
    ) {
        if currentConfirmation != nil || currentIgnoreAction != nil || isDismissing {
            queuedAlerts.append(QueuedAlert(title: title, message: message, color: color, onConfirm: onConfirm, onIgnore: onIgnore))
            return
        }
        currentConfirmation = onConfirm
        currentIgnoreAction = onIgnore
        self.currentTitle = title.isEmpty ? "定时提醒" : title
        self.currentMessage = message.isEmpty ? "时间已到" : message
        self.currentColor = color
        
        if alertWindow == nil {
            createAlertWindow()
        }
        
        guard let window = alertWindow else { return }
        
        let targetFrame = calculateTargetFrame(window: window)
        
        if !window.isVisible {
            // 平滑入场起始位置：微向上偏移 4pt，透明度为 0（无过冲、零回弹弹跳）
            let initialFrame = NSRect(
                x: targetFrame.origin.x,
                y: targetFrame.origin.y + 4,
                width: targetFrame.width,
                height: targetFrame.height
            )
            
            window.setFrame(initialFrame, display: false)
            window.alphaValue = 0.0
            window.orderFrontRegardless()
            
            // 单阶段平滑微滑入与淡入（0.16s，纯净确定性动效）
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1.0
                window.animator().setFrame(targetFrame, display: true)
            }
        } else {
            // 已展示状态下若有内容更新，平滑过渡尺寸和位置
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(targetFrame, display: true)
                window.animator().alphaValue = 1.0
            }
            window.orderFrontRegardless()
        }
        
        // 关键要求：绝不自动淡出！完全等待用户点击【我知道了/确认】才关闭！
    }
    
    private func calculateTargetFrame(window: NSPanel) -> NSRect {
        guard let hosting = window.contentViewController as? NSHostingController<TextAlertBubbleView> else {
            return NSRect(x: 0, y: 0, width: Self.cardWidth, height: 120)
        }
        
        // 强制重新计算并设定 SwiftUI 真实所需尺寸，杜绝高度测量滞后导致的向上偏移截断
        hosting.view.layoutSubtreeIfNeeded()
        let fittingSize = hosting.sizeThatFits(in: CGSize(width: Self.cardWidth, height: CGFloat.greatestFiniteMagnitude))
        let cardWidth = Self.cardWidth
        let cardHeight: CGFloat = max(110, fittingSize.height)
        
        let screen = StatusItemManager.shared.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let screenRect = screen.visibleFrame
        
        // 状态栏下沿在屏幕坐标系中的 Y 坐标为 screenRect.maxY
        // 窗口顶部距离菜单栏底沿留出 10pt 呼吸间距
        let targetY = screenRect.maxY - cardHeight - 10
        
        // 水平精准居中于状态栏按钮
        var targetX: CGFloat
        if let statusButton = StatusItemManager.shared.button,
           let btnWindow = statusButton.window {
            let buttonRectInWindow = statusButton.convert(statusButton.bounds, to: nil)
            let buttonRectOnScreen = btnWindow.convertToScreen(buttonRectInWindow)
            targetX = buttonRectOnScreen.midX - cardWidth / 2
        } else {
            targetX = screenRect.maxX - cardWidth - 16
        }
        
        // 边界安全约束：防止超出屏幕左、右、顶
        targetX = max(screenRect.minX + 16, min(targetX, screenRect.maxX - cardWidth - 16))
        let finalY = min(targetY, screenRect.maxY - cardHeight - 8)
        
        return NSRect(x: targetX, y: finalY, width: cardWidth, height: cardHeight)
    }
    
    /// 用户点击「好的」或「忽略」（轻微上收淡出）
    public func dismiss(ignored: Bool = false) {
        guard let window = alertWindow, window.isVisible, !isDismissing else { return }
        isDismissing = true
        window.makeFirstResponder(nil)
        let confirmation = currentConfirmation
        let ignoreAction = currentIgnoreAction
        currentConfirmation = nil
        currentIgnoreAction = nil
        if ignored {
            ignoreAction?()
        } else {
            confirmation?()
        }
        
        let exitFrame = NSRect(
            x: window.frame.origin.x,
            y: window.frame.origin.y + 4,
            width: window.frame.width,
            height: window.frame.height
        )
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0.0
            window.animator().setFrame(exitFrame, display: true)
        }, completionHandler: {
            Task { @MainActor [weak self] in
                window.orderOut(nil)
                guard let self else { return }
                self.isDismissing = false
                if !self.queuedAlerts.isEmpty {
                    let next = self.queuedAlerts.removeFirst()
                    self.show(
                        title: next.title,
                        message: next.message,
                        color: next.color,
                        onConfirm: next.onConfirm,
                        onIgnore: next.onIgnore
                    )
                }
            }
        })
    }
    
    private func createAlertWindow() {
        let hosting = NSHostingController(rootView: TextAlertBubbleView())
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.cardWidth, height: 120),
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
        // Clip the native hosting surface too, so material backing cannot fill the corners.
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.view.layer?.cornerRadius = Self.cornerRadius
        hosting.view.layer?.cornerCurve = .continuous
        hosting.view.layer?.masksToBounds = true
        
        self.alertWindow = panel
    }
}

// MARK: - 文本提醒确认气泡卡片（必须等待用户确认才关闭）
struct TextAlertBubbleView: View {
    @ObservedObject var hud = TextAlertHUD.shared
    
    var body: some View {
        VStack(spacing: 10) {
            // 顶排靠左：与主程序一致的品牌图标 + It's Time（尺寸锁定防止重排加宽）
            HStack {
                BrandTitleView()
                    .fixedSize()
                Spacer()
            }
            
            // 第二排：事项居中放置，放大字号并使用事件类型的专属颜色（标准系统字体，长文本自适应字号与换行）
            VStack(spacing: 4) {
                Text(hud.currentTitle)
                    .font(.system(size: hud.currentTitle.count > 25 ? 14 : (hud.currentTitle.count > 14 ? 16 : 18), weight: .regular))
                    .foregroundColor(hud.currentColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                
                // 若有不同的附加详情内容，在下方轻量展示
                if !hud.currentMessage.isEmpty && hud.currentMessage != hud.currentTitle && hud.currentMessage != "时间已到" {
                    Text(hud.currentMessage)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            
            // 底部操作区：左侧【忽略】，右侧【好的】
            HStack(spacing: 10) {
                Button(action: {
                    hud.dismiss(ignored: true)
                }) {
                    Text("忽略")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.07))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.primary.opacity(0.12), lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                
                Button(action: {
                    hud.dismiss(ignored: false)
                }) {
                    Text("好的")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 6)
                        .background(hud.currentColor)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(width: TextAlertHUD.cardWidth)
        .glassHUD(cornerRadius: TextAlertHUD.cornerRadius, accentColor: hud.currentColor, drawsShadow: false)
    }
}
