import SwiftUI
import AppKit
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        // 全面彻底禁用系统焦点框（Focus Ring）
        FocusRingManager.disableGlobally()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FocusRingManager.disableGlobally()
        
        // 设置通知代理，确保前后台均能收到通知横幅与提示音
        UNUserNotificationCenter.current().delegate = self
        
        // 初始化状态栏管理：接管系统菜单栏常驻、左键 Popover 与右键快捷上下文菜单
        StatusItemManager.shared.setup()
        
        // 启动时自动展开菜单栏主面板，让用户直观看到当前界面
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            StatusItemManager.shared.openPopover()
            if CommandLine.arguments.contains("--open-window") {
                WindowManager.shared.openMainWindow()
            }
        }
        
        // 延迟 10 秒静默检查更新，完全不影响启动性能
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            UpdateManager.shared.performDailySilentCheckIfNeeded()
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        StatusItemManager.shared.openPopover()
        WindowManager.shared.openMainWindow()
        return true
    }
    
    // UNUserNotificationCenterDelegate: 前台展示横幅和声音
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

@main
struct ItsTimeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
