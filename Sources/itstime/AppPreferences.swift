import Foundation
import Combine

/// 全屏或会议场景下的避让行为
public enum AvoidanceBehavior: String, Codable, CaseIterable, Identifiable {
    case skip = "skip"
    case silentNotification = "silentNotification"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .skip:
            return "跳过本次提醒"
        case .silentNotification:
            return "静默仅发系统通知"
        }
    }
}

/// 全局轻量偏好设置中心
@MainActor
public final class AppPreferences: ObservableObject {
    public static let shared = AppPreferences()
    
    private enum Keys {
        static let audioPreAlertSeconds = "ItsTime_Pref_AudioPreAlertSeconds"
        static let avoidanceEnabled = "ItsTime_Pref_AvoidanceEnabled"
        static let avoidanceBehavior = "ItsTime_Pref_AvoidanceBehavior"
        static let dndUntil = "ItsTime_Pref_DndUntil"
    }
    
    /// 音频任务触发前预告时长（秒）：0 表示关闭预告，支持 3 / 5 / 10 秒
    @Published public var audioPreAlertSeconds: Int {
        didSet {
            UserDefaults.standard.set(audioPreAlertSeconds, forKey: Keys.audioPreAlertSeconds)
        }
    }
    
    /// 是否开启全屏 / 会议自动避让
    @Published public var avoidanceEnabled: Bool {
        didSet {
            UserDefaults.standard.set(avoidanceEnabled, forKey: Keys.avoidanceEnabled)
        }
    }
    
    /// 触发避让时的处理方式
    @Published public var avoidanceBehavior: AvoidanceBehavior {
        didSet {
            UserDefaults.standard.set(avoidanceBehavior.rawValue, forKey: Keys.avoidanceBehavior)
        }
    }
    
    /// 临时免打扰截止时间（nil 表示未开启或已过期）
    @Published public var dndUntil: Date? {
        didSet {
            if let date = dndUntil {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Keys.dndUntil)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.dndUntil)
            }
        }
    }
    
    public var isDndActive: Bool {
        guard let until = dndUntil else { return false }
        return until > Date()
    }
    
    public init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.audioPreAlertSeconds) != nil {
            self.audioPreAlertSeconds = defaults.integer(forKey: Keys.audioPreAlertSeconds)
        } else {
            self.audioPreAlertSeconds = 5
        }
        
        self.avoidanceEnabled = defaults.bool(forKey: Keys.avoidanceEnabled)
        
        if let raw = defaults.string(forKey: Keys.avoidanceBehavior),
           let behavior = AvoidanceBehavior(rawValue: raw) {
            self.avoidanceBehavior = behavior
        } else {
            self.avoidanceBehavior = .skip
        }
        
        if defaults.object(forKey: Keys.dndUntil) != nil {
            let ts = defaults.double(forKey: Keys.dndUntil)
            let date = Date(timeIntervalSince1970: ts)
            self.dndUntil = date > Date() ? date : nil
        } else {
            self.dndUntil = nil
        }
    }
    
    // MARK: - 临时免打扰快捷控制
    
    public func enableDndForOneHour(from now: Date = Date()) {
        dndUntil = now.addingTimeInterval(3600)
    }
    
    public func enableDndUntilTomorrow(from now: Date = Date()) {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) {
            dndUntil = tomorrow
        }
    }
    
    public func clearDnd() {
        dndUntil = nil
    }
    
    public var dndRemainingDescription: String? {
        guard let until = dndUntil else { return nil }
        let remaining = Int(until.timeIntervalSinceNow)
        guard remaining > 0 else { return nil }
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        if hours > 0 {
            return "\(hours)小时\(minutes)分"
        }
        return "\(max(1, minutes))分钟"
    }
    
    // MARK: - Application Support 目录管理
    
    public static func appSupportDirectory(subpath: String? = nil) -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        var dir = base.appendingPathComponent("It's Time", isDirectory: true)
        if let subpath = subpath, !subpath.isEmpty {
            dir = dir.appendingPathComponent(subpath, isDirectory: true)
        }
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
