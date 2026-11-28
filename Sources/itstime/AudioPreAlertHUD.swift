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
    
    /// 展示或更新倒计时预告弹窗卡片（复用文本通知规范：居中于状态栏下方）
    public func update(alert: AudioPreAlertInfo) {
        self.currentAlert = alert
        
        if alertWindow == nil {
            createAlertWindow()
        }
        
        guard let window = alertWindow else { return }
        
        if !window.isVisible {
            // 首次展示：计算一次 frame，之后固定不再重算，避免每 tick setFrame 引起位移
            let targetFrame = calculateTargetFrame(window: window)
            let initialFrame = NSRect(
                x: targetFrame.origin.x,
                y: targetFrame.origin.y + 4,
                width: targetFrame.width,
                height: targetFrame.height
            )
            window.setFrame(initialFrame, display: false)
            window.alphaValue = 0.0
            window.orderFrontRegardless()
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1.0
                window.animator().setFrame(targetFrame, display: true)
            }
        }
        // 已展示时仅更新数据（currentAlert 已改），SwiftUI 自动重绘倒计时数字，窗口位置不动
    }
    
    /// 计算定位：精准水平居中于状态栏图标正下方（与文本通知卡片绝对对齐）
    private func calculateTargetFrame(window: NSPanel) -> NSRect {
        let cardWidth: CGFloat = 290
        let cardHeight: CGFloat = 148   // 固定高度，消除每 tick 重布局导致的位移抖动
        
        let screen = StatusItemManager.shared.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let screenRect = screen.visibleFrame
        
        var targetX: CGFloat
        if let statusButton = StatusItemManager.shared.button,
           let btnWindow = statusButton.window {
            let buttonRectInWindow = statusButton.convert(statusButton.bounds, to: nil)
            let buttonRectOnScreen = btnWindow.convertToScreen(buttonRectInWindow)
            targetX = buttonRectOnScreen.midX - cardWidth / 2
        } else {
            targetX = screenRect.maxX - cardWidth - 16
        }
        
        targetX = max(screenRect.minX + 16, min(targetX, screenRect.maxX - cardWidth - 16))
        let finalY = screenRect.maxY - cardHeight - 8
        
        return NSRect(x: targetX, y: finalY, width: cardWidth, height: cardHeight)
    }
    
    /// 倒计时结束或用户点击关闭时收起卡片
    public func dismiss() {
        self.currentAlert = nil
        guard let window = alertWindow, window.isVisible else { return }
        window.makeFirstResponder(nil)
        
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
        let hosting = NSHostingController(rootView: AudioPreAlertCardView())
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 290, height: 130),
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

// MARK: - 音频预告弹窗卡片视图（复用文本通知 UI 规范）
struct AudioPreAlertCardView: View {
    @ObservedObject var hud = AudioPreAlertHUD.shared
    
    var body: some View {
        if let alert = hud.currentAlert {
            VStack(spacing: 12) {
                // 顶排靠左：与主程序一致的品牌图标 + It's Time
                HStack {
                    BrandTitleView()
                        .fixedSize()
                    Spacer()
                    // 右上角：圆环倒计时
                    CountdownRingView(secondsRemaining: alert.secondsRemaining, total: 5)
                }
                
                // 中排：事项标题与即将播放提示
                VStack(spacing: 4) {
                    Text(alert.taskName)
                        .font(.system(size: alert.taskName.count > 20 ? 15 : 17, weight: .medium))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    let audioTitle = alert.audioName.isEmpty ? "本地音频" : alert.audioName
                    Text("即将播放: \(audioTitle)")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                
                // 底部操作区：醒目的【不播放】与【立即播放】
                HStack(spacing: 12) {
                    Button(action: {
                        SchedulerEngine.shared.skipAudioPreAlert()
                    }) {
                        Text("不播放")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    
                    Button(action: {
                        SchedulerEngine.shared.playAudioImmediatelyFromPreAlert()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9))
                            Text("立即播放")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background(Color.orange)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(16)
            .frame(width: 296, height: 152)
            .glassHUD(cornerRadius: 16, accentColor: .orange)
        } else {
            EmptyView()
        }
    }
}

// MARK: - 圆环倒计时组件
struct CountdownRingView: View {
    let secondsRemaining: Int
    let total: Int

    private var progress: Double {
        guard total > 0 else { return 0 }
        return Double(secondsRemaining) / Double(total)
    }

    var body: some View {
        ZStack {
            // 底层轨道
            Circle()
                .stroke(Color.orange.opacity(0.15), lineWidth: 3)

            // 进度弧（从顶部顺时针缩短）
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.9), value: progress)

            // 中心秒数
            Text("\(secondsRemaining)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.orange)
        }
        .frame(width: 30, height: 30)
    }
}
