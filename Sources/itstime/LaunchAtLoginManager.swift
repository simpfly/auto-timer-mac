import Foundation
import ServiceManagement
import Combine

@MainActor
public final class LaunchAtLoginManager: ObservableObject {
    public static let shared = LaunchAtLoginManager()
    
    @Published public private(set) var isEnabled: Bool = false
    
    private init() {
        refreshStatus()
    }
    
    /// 刷新当前系统自启动状态
    public func refreshStatus() {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            self.isEnabled = (status == .enabled)
        } else {
            self.isEnabled = false
        }
    }
    
    /// 切换开机自启动开关
    @discardableResult
    public func toggle() -> Bool {
        return setEnabled(!isEnabled)
    }
    
    /// 显式设置开机自启动状态
    @discardableResult
    public func setEnabled(_ enable: Bool) -> Bool {
        guard #available(macOS 13.0, *) else {
            print("⚠️ SMAppService 仅支持 macOS 13.0 及更高版本")
            return false
        }
        
        do {
            if enable {
                if SMAppService.mainApp.status == .enabled {
                    self.isEnabled = true
                    return true
                }
                try SMAppService.mainApp.register()
                print("✅ 成功注册开机自启动")
            } else {
                try SMAppService.mainApp.unregister()
                print("✅ 成功注销开机自启动")
            }
            refreshStatus()
            return true
        } catch {
            print("❌ 设置开机自启动失败: \(error.localizedDescription)")
            refreshStatus()
            return false
        }
    }
}
