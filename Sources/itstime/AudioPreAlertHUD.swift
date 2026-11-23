import SwiftUI
import AppKit

// MARK: - 音频预告信息
public struct AudioPreAlertInfo: Equatable {
    public let taskId: UUID
    public let taskName: String
    public let audioName: String
    public var secondsRemaining: Int
}

@MainActor
public final class AudioPreAlertHUD: ObservableObject {
    public static let shared = AudioPreAlertHUD()
    
    private var alertWindow: NSPanel?
    @Published public var currentAlert: AudioPreAlertInfo? = nil
    
    public init() {}
    
    /// 更新或展示倒计时预告（3s, 2s, 1s），初次出现时轻微弹动入场
    public func update(alert: AudioPreAlertInfo) {
        self.currentAlert = alert
        
        if alertWindow == nil {
            createAlertWindow()
        }
        
        guard let window = alertWindow else { return }
        
        // 目标定位：精准贴合在屏幕顶栏右侧菜单栏下方（安全边距 16pt，离顶 10pt）
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenRect = screen.visibleFrame
        let targetX = screenRect.maxX - window.frame.width - 16
        let targetY = screenRect.maxY - window.frame.height - 10
        let targetFrame = NSRect(x: targetX, y: targetY, width: window.frame.width, height: window.frame.height)
        
        if !window.isVisible {
            // 起始位置：轻度上浮 8pt
            let initialFrame = NSRect(x: targetX, y: targetY + 8, width: window.frame.width, height: window.frame.height)
            // 过冲位置：微弹过冲 2pt
            let overshootFrame = NSRect(x: targetX, y: targetY - 2, width: window.frame.width, height: window.frame.height)
            
            window.setFrame(initialFrame, display: false)
            window.alphaValue = 0.0
            window.orderFrontRegardless()
            
            // 阶段 1：快速滑落至过冲位置并淡入 (0.18s)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1.0
                window.animator().setFrame(overshootFrame, display: true)
            }, completionHandler: {
                // 阶段 2：轻柔回弹归位至目标位置 (0.10s)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.10
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().setFrame(targetFrame, display: true)
                }
            })
        }
        // 如果窗口已经可见（3s -> 2s -> 1s 倒计时进行中），仅静默更新内容，绝不重新触发布局位移引起抖动
    }
    
    /// 倒计时结束或跳过时关闭气泡（轻微上收淡出）
    public func dismiss() {
        self.currentAlert = nil
        guard let window = alertWindow, window.isVisible else { return }
        
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
            window.orderOut(nil)
        })
    }
    
    private func createAlertWindow() {
        let hosting = NSHostingController(rootView: AudioPreAlertBubbleView())
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 310, height: 86),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar // 浮动在状态栏级别，极显眼且不抢焦点
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentViewController = hosting
        
        self.alertWindow = panel
    }
}

// MARK: - 菜单栏下方预告气泡视图
struct AudioPreAlertBubbleView: View {
    @ObservedObject var hud = AudioPreAlertHUD.shared
    
    var body: some View {
        if let alert = hud.currentAlert {
            HStack(spacing: 12) {
                // 左侧倒计时胶囊徽章（3, 2, 1 递减）
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: 40, height: 40)
                    
                    Circle()
                        .stroke(Color.orange, lineWidth: 2.2)
                        .frame(width: 38, height: 38)
                    
                    Text("\(alert.secondsRemaining)s")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                        .monospacedDigit()
                }
                
                // 中间信息
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "bell.badge.waveform.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                        Text("即将播放音频")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.primary)
                    }
                    
                    Text(alert.taskName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary.opacity(0.9))
                        .lineLimit(1)
                    
                    if !alert.audioName.isEmpty {
                        Text(alert.audioName)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // 右侧：跳过按钮
                Button(action: {
                    SchedulerEngine.shared.skipAudioPreAlert()
                }) {
                    Text("跳过")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.14))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("取消本次音频播放")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.orange.opacity(0.35), lineWidth: 1.2)
            )
            .shadow(color: Color.black.opacity(0.16), radius: 14, x: 0, y: 8)
            .frame(width: 310, height: 86)
            .disableFocusEffect()
        } else {
            EmptyView()
        }
    }
}
