import AppKit
import SwiftUI

@MainActor
public final class WindowManager: NSObject, ObservableObject, NSWindowDelegate {
    public static let shared = WindowManager()
    
    private var window: NSWindow?
    private var calendarSyncWindow: NSWindow?
    private var updateWindow: NSWindow?
    private var preferencesWindow: NSWindow?
    private var aboutWindow: NSWindow?
    
    public override init() {
        super.init()
    }

    public func openNewReminder() {
        StatusItemManager.shared.openQuickReminder()
    }
    
    public func openMainWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        
        let hostingController = NSHostingController(rootView: MainWindowView())
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newWindow.center()
        newWindow.title = "It's Time"
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden // 沉浸式透明标题栏，界面更具原生 Glass 美感
        newWindow.isOpaque = false
        newWindow.backgroundColor = .clear
        newWindow.contentViewController = hostingController
        newWindow.isReleasedWhenClosed = false
        newWindow.minSize = NSSize(width: 520, height: 460)
        newWindow.delegate = self
        
        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    
    public func openCalendarSyncWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        
        if let existing = calendarSyncWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        
        let hostingController = NSHostingController(rootView: CalendarSyncSheet())
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.center()
        newWindow.title = "日历与提醒事项"
        newWindow.contentViewController = hostingController
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        
        self.calendarSyncWindow = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    
    public func closeCalendarSyncWindow() {
        hideWindow(calendarSyncWindow)
    }
    
    public func openUpdateWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        
        if let existing = updateWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        
        let hostingController = NSHostingController(rootView: UpdateSheetView())
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        newWindow.center()
        newWindow.title = "软件更新"
        newWindow.contentViewController = hostingController
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        
        self.updateWindow = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    
    public func closeUpdateWindow() {
        hideWindow(updateWindow)
    }
    
    public func openPreferencesWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        
        if let existing = preferencesWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        
        let hostingController = NSHostingController(rootView: PreferencesView())
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 370),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        newWindow.center()
        newWindow.title = "偏好设置"
        newWindow.contentViewController = hostingController
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        
        self.preferencesWindow = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    
    public func openAboutWindow() {
        StatusItemManager.shared.closePopover()
        NSApplication.shared.setActivationPolicy(.regular)

        if let existing = aboutWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let newWindow = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
        newWindow.styleMask = [.titled, .closable]
        newWindow.title = "关于 It's Time"
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.center()
        aboutWindow = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    public func openScreenTimeWindow() {
        StatusItemManager.shared.closePopover()
        openMainWindow()
        NotificationCenter.default.post(name: NSNotification.Name("ItsTime_ShowScreenTimePage"), object: nil)
    }
    
    private func hideWindow(_ window: NSWindow?) {
        guard let window else { return }
        window.makeFirstResponder(nil)
        window.orderOut(nil)
    }

    // NSWindowDelegate: 拦截窗口关闭，仅隐藏窗口，保留菜单栏继续后台执行
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideWindow(sender)
        return false
    }
}
