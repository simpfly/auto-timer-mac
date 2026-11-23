import AppKit
import ObjectiveC

/// 全局焦点环禁用管理器
/// 通过在 AppKit 运行时底层拦截 focusRingType 与 defaultFocusRingType，
/// 从系统绘制根基上彻底杜绝所有控件及视图出现紫蓝色系统焦点框（Focus Ring）。
public enum FocusRingManager {
    private static var isConfigured = false
    
    public static func disableGlobally() {
        guard !isConfigured else { return }
        isConfigured = true
        
        let noneBlock: @convention(block) (AnyObject) -> NSFocusRingType = { _ in .none }
        let imp = imp_implementationWithBlock(noneBlock)
        
        // 拦截 NSView, NSControl, NSCell 的实例 getter: focusRingType
        let classes: [AnyClass] = [NSView.self, NSControl.self, NSCell.self]
        for targetClass in classes {
            if let method = class_getInstanceMethod(targetClass, #selector(getter: NSView.focusRingType)) {
                method_setImplementation(method, imp)
            }
        }
        
        // 拦截 NSView 的类方法: defaultFocusRingType
        let classNoneBlock: @convention(block) (AnyClass) -> NSFocusRingType = { _ in .none }
        let classImp = imp_implementationWithBlock(classNoneBlock)
        if let classMethod = class_getClassMethod(NSView.self, #selector(getter: NSView.defaultFocusRingType)) {
            method_setImplementation(classMethod, classImp)
        }
    }
}
