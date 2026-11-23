import AppKit
import SwiftUI
import Combine

@MainActor
public final class StatusItemManager: NSObject, NSMenuDelegate {
    public static let shared = StatusItemManager()
    
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()
    
    public var button: NSStatusBarButton? {
        statusItem?.button
    }
    
    public override init() {
        super.init()
    }
    
    public func setup() {
        // 创建系统状态栏项
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        
        // 创建左键展开的主面板 Popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 540)
        popover.behavior = .transient
        popover.animates = false // 禁用动画防止弹窗产生微小位移抖动
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: MenuBarView())
        self.popover = popover
        
        // 绑定状态变化监听，实时更新状态栏图标与文字
        bindUpdates()
        
        // 初始化外观
        updateStatusItemAppearance()
    }
    
    private func bindUpdates() {
        SchedulerEngine.shared.$activeCountdownSummary
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemAppearance()
            }
            .store(in: &cancellables)
        
        SchedulerEngine.shared.$pendingAudioAlert
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemAppearance()
            }
            .store(in: &cancellables)
        
        AudioService.shared.$isPlaying
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemAppearance()
            }
            .store(in: &cancellables)
        
        AudioService.shared.$formattedRemainingTime
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemAppearance()
            }
            .store(in: &cancellables)
    }
    
    /// 动态刷新状态栏图标和文字
    private func updateStatusItemAppearance() {
        guard let button = statusItem?.button else { return }
        
        // 当 Popover 正在展开展示时，保持 statusItem 布局与宽度绝对静止，
        // 严禁在展开期间变更 button 文本导致宽度伸缩，从而引起弹窗窗口横向位移/跳动！
        if popover != nil && popover.isShown {
            return
        }
        
        if let preAlert = SchedulerEngine.shared.pendingAudioAlert {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
                .applying(.init(paletteColors: [.systemOrange]))
            button.image = NSImage(systemSymbolName: "bell.badge.waveform.fill", accessibilityDescription: "预告倒计时")?
                .withSymbolConfiguration(config)
            button.imagePosition = .imageLeft
            
            let attr = NSAttributedString(
                string: " \(preAlert.seconds)s",
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
                    .foregroundColor: NSColor.systemOrange
                ]
            )
            button.attributedTitle = attr
        } else if AudioService.shared.isPlaying {
            // 音频正在播放中：显示波形图标 + 实时剩余时间
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
                .applying(.init(paletteColors: [.systemGreen]))
            let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "正在播放音频")?
                .withSymbolConfiguration(config)
            button.image = image
            button.imagePosition = .imageLeft
            
            let remText = AudioService.shared.formattedRemainingTime
            let titleStr = remText.isEmpty ? "" : " \(remText)"
            let attr = NSAttributedString(
                string: titleStr,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
                    .foregroundColor: NSColor.systemGreen
                ]
            )
            button.attributedTitle = attr
        } else {
            let symbolName = "timer"
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "AutoTimer")?
                .withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeft
            
            if let summary = SchedulerEngine.shared.activeCountdownSummary {
                let attr = NSAttributedString(
                    string: " \(summary)",
                    attributes: [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                        .foregroundColor: NSColor.labelColor
                    ]
                )
                button.attributedTitle = attr
            } else {
                button.attributedTitle = NSAttributedString(string: "")
            }
        }
    }
    
    /// 状态栏点击响应（分发左键与右键）
    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        let isRightClick = event.type == .rightMouseUp ||
                           (event.type == .leftMouseUp && event.modifierFlags.contains(.control))
        
        if isRightClick {
            // 右键唤起快捷上下文菜单
            showContextMenu()
        } else {
            // 左键切换主面板展开/关闭
            togglePopover()
        }
    }
    
    /// 展开主面板展示
    public func openPopover() {
        guard let button = statusItem.button else { return }
        if !popover.isShown {
            NSApplication.shared.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    
    /// 切换左键主面板展示
    public func togglePopover() {
        guard let button = statusItem.button else { return }
        
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    
    /// 关闭主面板
    public func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }
    
    /// 弹出右键快捷菜单
    public func showContextMenu() {
        if popover.isShown {
            popover.performClose(nil)
        }
        
        let menu = buildContextMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }
    
    // MARK: - NSMenuDelegate
    public func menuDidClose(_ menu: NSMenu) {
        // 菜单关闭后，及时解绑 statusItem.menu，恢复常规左键点击分发
        statusItem.menu = nil
    }
    
    // MARK: - 构建右键快捷菜单
    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu(title: "AutoTimerContextMenu")
        
        // 1. 打开独立主窗口
        let mainWindowItem = NSMenuItem(
            title: "打开主窗口",
            action: #selector(openMainWindow),
            keyEquivalent: "o"
        )
        mainWindowItem.target = self
        mainWindowItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        menu.addItem(mainWindowItem)
        
        // 2. 日历与提醒事项
        let calendarItem = NSMenuItem(
            title: "日历与提醒事项",
            action: #selector(openCalendarSync),
            keyEquivalent: "c"
        )
        calendarItem.target = self
        calendarItem.image = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: nil)
        menu.addItem(calendarItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 3. 一键暂停 / 恢复所有任务
        let hasActive = SchedulerEngine.shared.hasActiveRunningTasks
        let pauseAllItem = NSMenuItem(
            title: hasActive ? "暂停所有任务" : "恢复所有任务",
            action: #selector(togglePauseAllTasks),
            keyEquivalent: "p"
        )
        pauseAllItem.target = self
        pauseAllItem.image = NSImage(
            systemSymbolName: hasActive ? "pause.circle" : "play.circle",
            accessibilityDescription: nil
        )
        menu.addItem(pauseAllItem)
        
        // 4. 正在播放音频时提供一键停止
        if AudioService.shared.isPlaying {
            let playingName = AudioService.shared.currentPlayingName
            let stopAudioItem = NSMenuItem(
                title: "停止播放: \(playingName)",
                action: #selector(stopAudio),
                keyEquivalent: "."
            )
            stopAudioItem.target = self
            stopAudioItem.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: nil)
            menu.addItem(stopAudioItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // 5. 开机自启动项（带复选勾选状态）
        LaunchAtLoginManager.shared.refreshStatus()
        let isLaunchEnabled = LaunchAtLoginManager.shared.isEnabled
        let launchItem = NSMenuItem(
            title: "开机自启动",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = isLaunchEnabled ? .on : .off
        launchItem.image = NSImage(systemSymbolName: "power.circle", accessibilityDescription: nil)
        menu.addItem(launchItem)
        
        // 6. 关于 AutoTimer
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let aboutItem = NSMenuItem(
            title: "关于 AutoTimer (v\(appVersion))",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 7. 退出 AutoTimer
        let quitItem = NSMenuItem(
            title: "退出 AutoTimer",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)
        
        return menu
    }
    
    // MARK: - 菜单 Action 响应
    @objc private func openCalendarSync() {
        closePopover()
        WindowManager.shared.openCalendarSyncWindow()
    }
    @objc private func showAbout() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel(
            options: [
                NSApplication.AboutPanelOptionKey.applicationName: "AutoTimer",
                NSApplication.AboutPanelOptionKey.version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
            ]
        )
    }
    
    @objc private func toggleLaunchAtLogin() {
        LaunchAtLoginManager.shared.toggle()
    }
    
    @objc private func openMainWindow() {
        closePopover()
        WindowManager.shared.openMainWindow()
    }
    
    @objc private func togglePauseAllTasks() {
        SchedulerEngine.shared.togglePauseAll()
    }
    
    @objc private func stopAudio() {
        AudioService.shared.stop(fadeOut: true)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - NSPopoverDelegate
extension StatusItemManager: NSPopoverDelegate {
    public func popoverDidClose(_ notification: Notification) {
        // 弹窗关闭后，立即刷新状态栏文字与图标，恢复实时更新
        updateStatusItemAppearance()
    }
}
