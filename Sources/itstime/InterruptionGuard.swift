import Foundation
import AppKit
import CoreGraphics
import CoreAudio

/// 全屏应用与语音会议检测器（零辅助功能权限开销）
public enum InterruptionGuard {
    
    /// 检查当前是否处于应避让状态（全屏应用或麦克风活跃）
    public static func shouldAvoidNow() -> Bool {
        return isFullScreenAppActive() || isMicrophoneActive()
    }
    
    /// 检测当前前台是否存在覆盖整个屏幕的非系统桌面窗口
    public static func isFullScreenAppActive() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        let frontPID = frontApp.processIdentifier
        if frontPID == ProcessInfo.processInfo.processIdentifier {
            return false
        }
        // 排除 Finder 桌面本身
        if frontApp.bundleIdentifier == "com.apple.finder" {
            return false
        }
        
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return false }
        
        for info in infoList {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid == frontPID,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            
            // 判断窗口尺寸是否接近或等于任一屏幕尺寸（容差 4pt）
            for screen in screens {
                let frame = screen.frame
                if abs(bounds.width - frame.width) <= 4 && abs(bounds.height - frame.height) <= 4 {
                    return true
                }
            }
        }
        return false
    }
    
    /// 通过 CoreAudio 检测默认输入设备（麦克风）是否正在被采集使用
    public static func isMicrophoneActive() -> Bool {
        var defaultDeviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &defaultDeviceID
        )
        guard status == noErr, defaultDeviceID != kAudioDeviceUnknown else {
            return false
        }
        
        var isRunning: UInt32 = 0
        var runSize = UInt32(MemoryLayout<UInt32>.size)
        var runAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let runStatus = AudioObjectGetPropertyData(
            defaultDeviceID,
            &runAddress,
            0,
            nil,
            &runSize,
            &isRunning
        )
        return runStatus == noErr && isRunning != 0
    }
}
