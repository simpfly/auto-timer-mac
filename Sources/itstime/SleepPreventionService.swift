import Foundation
import IOKit.pwr_mgt

@MainActor
public final class SleepPreventionService {
    public static let shared = SleepPreventionService()
    
    private var assertionID: IOPMAssertionID = 0
    private var isPreventingSleep: Bool = false
    
    /// 开始阻止系统休眠（音频播放或重要倒计时期间）
    public func startPreventingSleep(reason: String = "It's Time 正在执行定时音频播放") {
        guard !isPreventingSleep else { return }
        
        let success = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        
        if success == kIOReturnSuccess {
            isPreventingSleep = true
        }
    }
    
    /// 释放休眠阻止
    public func stopPreventingSleep() {
        guard isPreventingSleep else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isPreventingSleep = false
    }
}
