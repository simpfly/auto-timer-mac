import Foundation
import AVFoundation
import AppKit

@MainActor
public final class AudioService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    public static let shared = AudioService()
    
    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var currentPlayingName: String = ""
    @Published public private(set) var remainingSeconds: Int = 0
    @Published public private(set) var formattedRemainingTime: String = ""
    @Published public var volume: Double = 0.8 {
        didSet {
            if !isFading {
                player?.volume = Float(volume)
            }
        }
    }
    @Published public private(set) var isMuted: Bool = false
    
    private var player: AVAudioPlayer?
    private var durationTimer: Timer?
    private var fadeTimer: Timer?
    private var previousVolume: Double = 0.8
    private var isFading: Bool = false
    
    public override init() {
        super.init()
    }
    
    /// 解析音频路径：支持 file:// 协议与百分号编码、优先绝对路径，若失效则在 Bundle Resources、当前目录及多级工程目录中智能查找
    public static func resolveAudioURL(for rawPath: String) -> URL? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // 1. 去除 file:// 协议头及 URL 编码
        var cleanPath = trimmed
        if cleanPath.hasPrefix("file://") {
            if let parsed = URL(string: cleanPath)?.path {
                cleanPath = parsed
            } else {
                cleanPath = String(cleanPath.dropFirst(7))
            }
        }
        cleanPath = cleanPath.removingPercentEncoding ?? cleanPath
        
        // 2. 检查绝对路径或直接相对路径
        if FileManager.default.fileExists(atPath: cleanPath) {
            return URL(fileURLWithPath: cleanPath)
        }
        
        let filename = (cleanPath as NSString).lastPathComponent
        guard !filename.isEmpty else { return nil }
        
        // 3. 检查 App Bundle Resources
        if let resURL = Bundle.main.resourceURL {
            let candidates = [
                resURL.appendingPathComponent("Audio").appendingPathComponent(filename),
                resURL.appendingPathComponent(filename),
                resURL.appendingPathComponent("Resources/Audio").appendingPathComponent(filename)
            ]
            for candidate in candidates {
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        
        // 4. 检查 App Bundle 目录结构 (Contents/Resources)
        let bundleURL = Bundle.main.bundleURL
        let inBundleContents = bundleURL.appendingPathComponent("Contents/Resources/Audio").appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: inBundleContents.path) {
            return inBundleContents
        }
        let inBundleRoot = bundleURL.appendingPathComponent("Contents/Resources").appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: inBundleRoot.path) {
            return inBundleRoot
        }
        
        // 5. 检查当前工作目录及标准相对路径
        let currentCandidates = [
            URL(fileURLWithPath: "Resources/Audio").appendingPathComponent(filename),
            URL(fileURLWithPath: "Resources").appendingPathComponent(filename),
            URL(fileURLWithPath: filename)
        ]
        for candidate in currentCandidates {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        
        // 6. 检查可执行文件所在目录及其父级目录（适配 swift run / 命令行构建）
        if let execPath = Bundle.main.executablePath {
            let execDir = URL(fileURLWithPath: execPath).deletingLastPathComponent()
            let checkDirs = [
                execDir,
                execDir.deletingLastPathComponent(),
                execDir.deletingLastPathComponent().deletingLastPathComponent()
            ]
            for dir in checkDirs {
                let candidate = dir.appendingPathComponent("Resources/Audio").appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        
        return nil
    }
    
    /// 播放指定的本地文件路径，支持平滑淡入（Fade In）
    @discardableResult
    public func playLocalFile(
        atPath filePath: String,
        displayName: String,
        loop: Bool = false,
        volume: Double = 0.8,
        durationSeconds: Int? = nil,
        fadeIn: Bool = true
    ) -> Bool {
        guard let fileURL = AudioService.resolveAudioURL(for: filePath) else {
            print("❌ 本地音频文件不存在且无法解析: \(filePath)")
            playNotificationChime()
            return false
        }
        
        // 先完全停止旧播放
        stopImmediately()
        
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: fileURL)
            newPlayer.delegate = self
            newPlayer.numberOfLoops = loop ? -1 : 0
            
            let targetVolume = Float(max(0.01, min(1.0, volume)))
            if fadeIn {
                // 起步给予 40% 的起始音量，消除等待感与死寂感，同时具备柔和过渡
                newPlayer.volume = targetVolume * 0.4
            } else {
                newPlayer.volume = targetVolume
            }
            newPlayer.prepareToPlay()
            let started = newPlayer.play()
            if !started {
                print("❌ AVAudioPlayer.play() 启动失败")
                playNotificationChime()
                return false
            }
            
            self.player = newPlayer
            self.volume = volume
            self.currentPlayingName = displayName.isEmpty ? fileURL.lastPathComponent : displayName
            self.isPlaying = true
            self.isMuted = false
            
            // 阻止系统休眠
            SleepPreventionService.shared.startPreventingSleep()
            
            // 启动音频播放剩余时间实时跟踪
            startProgressTracking(totalLimit: durationSeconds)
            
            // 平滑轻柔淡入 (快速平滑 0.4 秒，消除等待感)
            if fadeIn {
                performFade(from: targetVolume * 0.4, to: targetVolume, duration: 0.4)
            }
            
            // 若有限制时长
            if let duration = durationSeconds, duration > 0 {
                durationTimer?.invalidate()
                durationTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(duration), repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        self?.stop(fadeOut: true)
                    }
                }
            }
            return true
        } catch {
            print("❌ 播放失败: \(error.localizedDescription)")
            playNotificationChime()
            SleepPreventionService.shared.stopPreventingSleep()
            return false
        }
    }
    
    /// 平滑淡入/淡出辅助
    private func performFade(from startVol: Float, to endVol: Float, duration: TimeInterval, completion: (() -> Void)? = nil) {
        fadeTimer?.invalidate()
        isFading = true
        
        let steps = 12
        let stepInterval = duration / Double(steps)
        let volDelta = (endVol - startVol) / Float(steps)
        var currentStep = 0
        var currentVol = startVol
        
        let timer = Timer(timeInterval: stepInterval, repeats: true) { [weak self] t in
            Task { @MainActor [weak self] in
                guard let self = self, let player = self.player else {
                    t.invalidate()
                    return
                }
                
                currentStep += 1
                currentVol += volDelta
                player.volume = max(0.0, min(1.0, currentVol))
                
                if currentStep >= steps {
                    t.invalidate()
                    player.volume = endVol
                    self.isFading = false
                    completion?()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.fadeTimer = timer
    }
    
    /// 停止播放（默认支持平滑淡出 Fade Out）
    public func stop(fadeOut: Bool = true) {
        durationTimer?.invalidate()
        durationTimer = nil
        
        guard let p = player, isPlaying else {
            stopImmediately()
            return
        }
        
        if fadeOut && p.volume > 0.1 {
            performFade(from: p.volume, to: 0.0, duration: 0.4) { [weak self] in
                self?.stopImmediately()
            }
        } else {
            stopImmediately()
        }
    }
    
    private var progressTimer: Timer?
    
    /// 实时跟踪并发布剩余时间
    private func startProgressTracking(totalLimit: Int?) {
        progressTimer?.invalidate()
        updateRemainingTime(totalLimit: totalLimit)
        
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateRemainingTime(totalLimit: totalLimit)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.progressTimer = timer
    }
    
    private func updateRemainingTime(totalLimit: Int?) {
        guard let p = player, isPlaying else {
            remainingSeconds = 0
            formattedRemainingTime = ""
            return
        }
        
        let remaining: Double
        if let limit = totalLimit, limit > 0 {
            remaining = max(0, Double(limit) - p.currentTime)
        } else if p.duration > 0 && p.numberOfLoops == 0 {
            remaining = max(0, p.duration - p.currentTime)
        } else {
            let cur = Int(p.currentTime)
            let m = cur / 60
            let s = cur % 60
            remainingSeconds = cur
            formattedRemainingTime = String(format: "%02d:%02d", m, s)
            return
        }
        
        let sec = Int(ceil(remaining))
        remainingSeconds = sec
        let m = sec / 60
        let s = sec % 60
        formattedRemainingTime = String(format: "%02d:%02d", m, s)
    }
    
    private func stopImmediately() {
        progressTimer?.invalidate()
        progressTimer = nil
        remainingSeconds = 0
        formattedRemainingTime = ""
        
        fadeTimer?.invalidate()
        fadeTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
        isFading = false
        
        player?.stop()
        player = nil
        isPlaying = false
        currentPlayingName = ""
        
        SleepPreventionService.shared.stopPreventingSleep()
    }
    
    /// 切换静音
    public func toggleMute() {
        if isMuted {
            isMuted = false
            volume = previousVolume > 0 ? previousVolume : 0.8
            player?.volume = Float(volume)
        } else {
            previousVolume = volume
            isMuted = true
            player?.volume = 0
        }
    }
    
    // MARK: - 专属温和通知提示音 (Chime)
    private var chimePlayer: AVAudioPlayer?
    
    /// 播放温和空灵的到期专属提示音（柔和起音、无爆音、平滑衰减）
    public func playNotificationChime(volume: Double = 0.85) {
        let chimeURL = AudioService.resolveAudioURL(for: "Resources/Audio/notification.aiff")
            ?? AudioService.resolveAudioURL(for: "Resources/Audio/notification.wav")
            ?? AudioService.resolveAudioURL(for: "notification.aiff")
            ?? AudioService.resolveAudioURL(for: "notification.wav")
            
        if let url = chimeURL {
            do {
                let p = try AVAudioPlayer(contentsOf: url)
                p.volume = Float(max(0.05, min(1.0, volume)))
                p.prepareToPlay()
                p.play()
                self.chimePlayer = p
                return
            } catch {
                print("❌ 播放专属提示音失败: \(error.localizedDescription)")
            }
        }
        
        NSSound(named: "Glass")?.play()
    }

    // AVAudioPlayerDelegate
    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stopImmediately()
        }
    }
    
    // MARK: - 自定义音频文件托管
    
    /// 获取应用托管音频目录（Application Support/It's Time/Audio）
    public static func managedAudioDirectory() -> URL {
        AppPreferences.appSupportDirectory(subpath: "Audio")
    }
    
    /// 将用户选择的外部音频拷贝至应用托管目录，防止原文件被移动/重命名后失效
    public static func importManagedAudio(from sourceURL: URL, into directory: URL? = nil) -> String {
        let targetDir = directory ?? managedAudioDirectory()
        let fm = FileManager.default
        if !fm.fileExists(atPath: targetDir.path) {
            try? fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
        }
        
        let standardizedSource = sourceURL.standardizedFileURL.path
        let standardizedDir = targetDir.standardizedFileURL.path
        if standardizedSource.hasPrefix(standardizedDir + "/") {
            return sourceURL.path
        }
        
        let destName = "\(UUID().uuidString.prefix(8))_\(sourceURL.lastPathComponent)"
        let destURL = targetDir.appendingPathComponent(destName)
        do {
            try fm.copyItem(at: sourceURL, to: destURL)
            return destURL.path
        } catch {
            print("⚠️ 拷贝托管音频失败，回退使用原路径: \(error.localizedDescription)")
            return sourceURL.path
        }
    }
    
    /// 清理不再被任何任务引用的托管音频文件
    public static func cleanupOrphanedManagedAudio(referencedPaths: [String], in directory: URL? = nil) {
        let targetDir = directory ?? managedAudioDirectory()
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: targetDir, includingPropertiesForKeys: nil) else {
            return
        }
        
        let referencedSet = Set(referencedPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        for fileURL in contents {
            let path = fileURL.standardizedFileURL.path
            if !referencedSet.contains(path) {
                try? fm.removeItem(at: fileURL)
            }
        }
    }
}
