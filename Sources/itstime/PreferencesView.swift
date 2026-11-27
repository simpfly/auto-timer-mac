import SwiftUI
import AppKit

/// 轻量偏好设置窗口视图
public struct PreferencesView: View {
    @ObservedObject private var prefs = AppPreferences.shared
    @ObservedObject private var scheduler = SchedulerEngine.shared
    @ObservedObject private var launchManager = LaunchAtLoginManager.shared
    @ObservedObject private var updateManager = UpdateManager.shared
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                generalSection
                reminderAndDndSection
            }
            .padding(22)
        }
        .frame(width: 440, height: 370)
        .background(.regularMaterial)
        .onAppear {
            launchManager.refreshStatus()
        }
    }
    
    private var headerSection: some View {
        HStack {
            Text("偏好设置")
                .font(.system(size: 18, weight: .semibold))
            Spacer()
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - 1. 通用
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("通用")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            VStack(spacing: 0) {
                HStack {
                    Label("开机自启动", systemImage: "power.circle")
                        .font(.system(size: 13))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { launchManager.isEnabled },
                        set: { _ in launchManager.toggle() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                
                Divider().padding(.leading, 14)
                
                HStack {
                    Label("软件更新", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13))
                    Spacer()
                    Button("检查更新") {
                        updateManager.checkForUpdates(userInitiated: true)
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(Color.primary.opacity(0.04))
            .cornerRadius(10)
        }
    }
    
    // MARK: - 2. 提醒与免打扰
    private var reminderAndDndSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("提醒与免打扰")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            VStack(spacing: 0) {
                HStack {
                    Label("音频预告时长", systemImage: "bell.badge.waveform")
                        .font(.system(size: 13))
                    Spacer()
                    Picker("", selection: $prefs.audioPreAlertSeconds) {
                        Text("关闭").tag(0)
                        Text("3 秒").tag(3)
                        Text("5 秒").tag(5)
                        Text("10 秒").tag(10)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                
                Divider().padding(.leading, 14)
                
                HStack {
                    Label("临时免打扰", systemImage: "moon.zzz")
                        .font(.system(size: 13))
                    Spacer()
                    if prefs.isDndActive, let rem = prefs.dndRemainingDescription {
                        Text("剩余 \(rem)")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Button("恢复") {
                            scheduler.clearDnd()
                        }
                        .controlSize(.small)
                    } else {
                        Button("1 小时") {
                            scheduler.enableDndForOneHour()
                        }
                        .controlSize(.small)
                        Button("今日") {
                            scheduler.enableDndUntilTomorrow()
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                
                Divider().padding(.leading, 14)
                
                HStack {
                    Label("全屏 / 会议自动避让", systemImage: "rectangle.inset.filled.and.person.filled")
                        .font(.system(size: 13))
                    Spacer()
                    Toggle("", isOn: $prefs.avoidanceEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                
                if prefs.avoidanceEnabled {
                    Divider().padding(.leading, 14)
                    HStack {
                        Text("避让方式")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $prefs.avoidanceBehavior) {
                            ForEach(AvoidanceBehavior.allCases) { behavior in
                                Text(behavior.displayName).tag(behavior)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 165)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
            .background(Color.primary.opacity(0.04))
            .cornerRadius(10)
        }
    }
}
