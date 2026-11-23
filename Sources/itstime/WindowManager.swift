import AppKit
import SwiftUI

@MainActor
public final class WindowManager: NSObject, ObservableObject, NSWindowDelegate {
    public static let shared = WindowManager()
    
    private var window: NSWindow?
    private var calendarSyncWindow: NSWindow?
    
    public override init() {
        super.init()
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
        calendarSyncWindow?.orderOut(nil)
    }
    
    // NSWindowDelegate: 拦截窗口关闭，仅隐藏窗口，保留菜单栏继续后台执行
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
