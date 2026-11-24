import SwiftUI
import AppKit

// MARK: - 软件更新弹窗面板
public struct UpdateSheetView: View {
    @ObservedObject var updateManager = UpdateManager.shared
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // 顶栏：应用图标与标题
            headerView
                .padding(.top, 24)
                .padding(.horizontal, 24)
            
            Divider()
                .opacity(0.2)
                .padding(.vertical, 16)
            
            // 动态内容区（根据 UpdateManager.state 分发）
            contentBody
                .padding(.horizontal, 24)
            
            Spacer(minLength: 16)
            
            // 底栏操作按钮
            footerActions
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .frame(width: 440, height: 380)
        .background(.regularMaterial)
        .disableFocusEffect()
    }
    
    // MARK: - 顶栏
    private var headerView: some View {
        HStack(spacing: 14) {
            if let icon = NSImage(named: "AppIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .cornerRadius(10)
            } else {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text("软件更新")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("当前版本: v\(updateManager.currentVersionString)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    // MARK: - 状态内容分发
    @ViewBuilder
    private var contentBody: some View {
        switch updateManager.state {
        case .checking:
            VStack(spacing: 14) {
                Spacer()
                ProgressView()
                    .scaleEffect(0.9)
                Text("正在检查更新...")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            
        case .upToDate:
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.green)
                
                Text("当前已是最新版本")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                Text("It's Time 处于最新状态，无需更新。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            
        case let .updateAvailable(version, releaseNotes, _, downloadURL, _):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("发现新版本")
                        .font(.system(size: 14, weight: .semibold))
                    Text(version)
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .cornerRadius(6)
                    
                    Spacer()
                    
                    if downloadURL != nil {
                        Text("支持一键原地升级")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                Text("更新日志")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                ScrollView(showsIndicators: true) {
                    Text(releaseNotes)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 140)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 0.8)
                )
            }
            
        case let .downloading(progress):
            VStack(spacing: 16) {
                Spacer()
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("正在下载更新包...")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.accentColor)
                    }
                    
                    ProgressView(value: progress, total: 1.0)
                        .progressViewStyle(.linear)
                }
                .padding(.horizontal, 4)
                
                Text("下载完成后将自动安全替换并秒级重启")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
        case .readyToInstall:
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.accentColor)
                
                Text("更新包已准备就绪")
                    .font(.system(size: 14, weight: .semibold))
                
                Text("点击下方按钮将自动替换旧版本并重新启动应用。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            
        case .installing:
            VStack(spacing: 14) {
                Spacer()
                ProgressView()
                    .scaleEffect(0.9)
                Text("正在就地更新并重启 It's Time...")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            
        case let .error(message):
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 34))
                    .foregroundColor(.orange)
                
                Text("检查更新失败")
                    .font(.system(size: 14, weight: .semibold))
                
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                Spacer()
            }
        case .idle:
            EmptyView()
        }
    }
    
    // MARK: - 底栏动作按钮
    @ViewBuilder
    private var footerActions: some View {
        HStack(spacing: 12) {
            switch updateManager.state {
            case .checking:
                Spacer()
                Button("取消") {
                    dismissView()
                }
                .keyboardShortcut(.cancelAction)
                
            case .upToDate:
                Spacer()
                Button("好") {
                    dismissView()
                }
                .keyboardShortcut(.defaultAction)
                
            case let .updateAvailable(_, _, releaseURL, downloadURL, _):
                // 网页查看辅助
                Button("在浏览器查看") {
                    NSWorkspace.shared.open(releaseURL)
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
                
                Spacer()
                
                Button("稍后") {
                    dismissView()
                }
                .keyboardShortcut(.cancelAction)
                
                if downloadURL != nil {
                    Button("立即更新并重启") {
                        updateManager.startDownload()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("前往下载页面") {
                        NSWorkspace.shared.open(releaseURL)
                        dismissView()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
                
            case .downloading:
                Spacer()
                Button("取消下载") {
                    updateManager.cancelDownload()
                    dismissView()
                }
                
            case .readyToInstall:
                Spacer()
                Button("稍后重启") {
                    dismissView()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("立即重启更新") {
                    updateManager.installAndRelaunch()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                
            case .installing:
                Spacer()
                Text("正在完成...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                
            case .error:
                Spacer()
                Button("关闭") {
                    dismissView()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("重试") {
                    updateManager.checkForUpdates(userInitiated: true)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                
            case .idle:
                Spacer()
                Button("关闭") {
                    dismissView()
                }
            }
        }
    }
    
    private func dismissView() {
        updateManager.reset()
        WindowManager.shared.closeUpdateWindow()
        dismiss()
    }
}
