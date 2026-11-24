import Foundation
import AppKit
import Combine

// MARK: - GitHub Release 结构定义
public struct GitHubRelease: Codable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlURL: String
    public let publishedAt: String?
    public let assets: [GitHubAsset]
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

public struct GitHubAsset: Codable {
    public let name: String
    public let browserDownloadURL: String
    public let size: Int
    public let contentType: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
        case contentType = "content_type"
    }
}

// MARK: - 语义化版本比对工具
public struct SemVer: Comparable, Equatable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let raw: String
    
    public init(_ rawString: String) {
        self.raw = rawString
        // 过滤掉前导 "v" 或 "V"，分割点号
        let clean = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        
        let components = clean.split(separator: ".").compactMap { Int($0) }
        self.major = components.indices.contains(0) ? components[0] : 0
        self.minor = components.indices.contains(1) ? components[1] : 0
        self.patch = components.indices.contains(2) ? components[2] : 0
    }
    
    public static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
    
    public static func == (lhs: SemVer, rhs: SemVer) -> Bool {
        return lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch
    }
}

// MARK: - 更新管理核心服务
@MainActor
public final class UpdateManager: NSObject, ObservableObject {
    public static let shared = UpdateManager()
    
    // GitHub 仓库配置
    public static let repoOwner = "simpfly"
    public static let repoName = "its-time-mac"
    public static let latestReleaseURLString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
    
    // 状态定义
    public enum UpdateState: Equatable {
        case idle
        case checking
        case updateAvailable(version: String, releaseNotes: String, releaseURL: URL, downloadURL: URL?, assetSize: Int?)
        case upToDate
        case downloading(progress: Double)
        case readyToInstall(extractedAppURL: URL)
        case installing
        case error(String)
        
        public static func == (lhs: UpdateState, rhs: UpdateState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.checking, .checking), (.upToDate, .upToDate), (.installing, .installing):
                return true
            case let (.updateAvailable(v1, _, _, _, _), .updateAvailable(v2, _, _, _, _)):
                return v1 == v2
            case let (.downloading(p1), .downloading(p2)):
                return abs(p1 - p2) < 0.0001
            case let (.readyToInstall(u1), .readyToInstall(u2)):
                return u1 == u2
            case let (.error(e1), .error(e2)):
                return e1 == e2
            default:
                return false
            }
        }
    }
    
    @Published public private(set) var state: UpdateState = .idle
    @Published public var isSheetPresented: Bool = false {
        didSet {
            if isSheetPresented {
                WindowManager.shared.openUpdateWindow()
            } else {
                WindowManager.shared.closeUpdateWindow()
            }
        }
    }
    
    // 记录是否是用户主动点击检查（用于区分“已是最新”时是否弹出轻量提示）
    public private(set) var isUserInitiatedCheck: Bool = false
    
    private var downloadTask: URLSessionDownloadTask?
    private var downloadDelegateBridge: DownloadDelegateBridge?
    
    // 当前版本
    public var currentVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    private let lastCheckKey = "ItsTime_LastUpdateCheckDate"
    
    public override init() {
        super.init()
    }
    
    // MARK: - 检查更新入口
    public func checkForUpdates(userInitiated: Bool = true) {
        self.isUserInitiatedCheck = userInitiated
        self.state = .checking
        if userInitiated {
            self.isSheetPresented = true
        }
        
        guard let url = URL(string: Self.latestReleaseURLString) else {
            self.state = .error("无效的检查更新地址")
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("It's-Time-UpdateChecker", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.state = .error("网络请求无有效响应")
                    return
                }
                
                if httpResponse.statusCode == 404 {
                    // 尚未发布 release
                    self.state = .upToDate
                    return
                }
                
                guard httpResponse.statusCode == 200 else {
                    self.state = .error("检查更新失败 (HTTP \(httpResponse.statusCode))")
                    return
                }
                
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                self.processReleaseResult(release)
                
                // 记录成功检查的日期
                UserDefaults.standard.set(Date(), forKey: self.lastCheckKey)
            } catch {
                self.state = .error("连接失败: \(error.localizedDescription)")
            }
        }
    }
    
    /// 每日后台自动静默检查
    public func performDailySilentCheckIfNeeded() {
        let lastDate = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? Date.distantPast
        let oneDayInSeconds: TimeInterval = 24 * 3600
        if Date().timeIntervalSince(lastDate) >= oneDayInSeconds {
            checkForUpdates(userInitiated: false)
        }
    }
    
    // MARK: - 处理 Release 结果
    private func processReleaseResult(_ release: GitHubRelease) {
        let latestSemVer = SemVer(release.tagName)
        let currentSemVer = SemVer(currentVersionString)
        
        if latestSemVer > currentSemVer {
            // 匹配可用更新安装包
            // 优先查找 .zip 文件（如 It's Time.zip, itstime.zip 或任意 zip asset）
            let zipAsset = release.assets.first(where: {
                $0.name.lowercased().hasSuffix(".zip")
            })
            
            let downloadURL = zipAsset.flatMap { URL(string: $0.browserDownloadURL) }
            let releasePageURL = URL(string: release.htmlURL) ?? URL(string: "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases")!
            let notes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "体验优化与缺陷修复。"
            
            self.state = .updateAvailable(
                version: release.tagName,
                releaseNotes: notes,
                releaseURL: releasePageURL,
                downloadURL: downloadURL,
                assetSize: zipAsset?.size
            )
            // 静默检查若发现有新版，弹出提示窗口
            self.isSheetPresented = true
        } else {
            self.state = .upToDate
            // 若为静默检查且已是最新，则不打扰用户，自动重置为空闲
            if !isUserInitiatedCheck {
                self.isSheetPresented = false
            }
        }
    }
    
    // MARK: - 下载更新包
    public func startDownload() {
        guard case let .updateAvailable(_, _, releaseURL, downloadURL, _) = state else {
            return
        }
        
        // 若 release 中没有上传 zip 资产包，则退化为直接在浏览器打开 Release 页面
        guard let downloadURL = downloadURL else {
            NSWorkspace.shared.open(releaseURL)
            self.state = .idle
            self.isSheetPresented = false
            return
        }
        
        self.state = .downloading(progress: 0.0)
        
        var request = URLRequest(url: downloadURL)
        request.setValue("It's-Time-UpdateChecker", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 120
        
        let bridge = DownloadDelegateBridge(
            onProgress: { [weak self] progress in
                Task { @MainActor in
                    guard let self = self else { return }
                    if case .downloading = self.state {
                        self.state = .downloading(progress: progress)
                    }
                }
            },
            onFinished: { [weak self] location in
                Task { @MainActor in
                    self?.handleDownloadFinished(location: location)
                }
            },
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.state = .error("下载失败: \(error.localizedDescription)")
                }
            }
        )
        self.downloadDelegateBridge = bridge
        
        let session = URLSession(configuration: .default, delegate: bridge, delegateQueue: nil)
        let task = session.downloadTask(with: request)
        self.downloadTask = task
        task.resume()
    }
    
    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadDelegateBridge = nil
        self.state = .idle
    }
    
    private func handleDownloadFinished(location: URL) {
        do {
            let fileManager = FileManager.default
            let tempDir = fileManager.temporaryDirectory.appendingPathComponent("ItsTimeUpdate_\(UUID().uuidString)")
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            let tempZipPath = tempDir.appendingPathComponent("update.zip")
            try fileManager.moveItem(at: location, to: tempZipPath)
            
            // 使用 macOS 原生 ditto 工具安全解压（保留代码签名、软链接与权限）
            let extractDir = tempDir.appendingPathComponent("extracted")
            try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)
            
            let dittoProcess = Process()
            dittoProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            dittoProcess.arguments = ["-xk", tempZipPath.path, extractDir.path]
            try dittoProcess.run()
            dittoProcess.waitUntilExit()
            
            guard dittoProcess.terminationStatus == 0 else {
                throw NSError(domain: "UpdateError", code: 1, userInfo: [NSLocalizedDescriptionKey: "解压更新包失败"])
            }
            
            // 搜索解压目录中的 .app Bundle
            let extractedApp = try findAppBundle(in: extractDir)
            guard let validApp = extractedApp else {
                throw NSError(domain: "UpdateError", code: 2, userInfo: [NSLocalizedDescriptionKey: "更新包中未找到有效的应用 Bundle"])
            }
            
            self.state = .readyToInstall(extractedAppURL: validApp)
        } catch {
            self.state = .error("更新包处理失败: \(error.localizedDescription)")
        }
    }
    
    private func findAppBundle(in directory: URL) throws -> URL? {
        let fileManager = FileManager.default
        let items = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for item in items {
            if item.pathExtension == "app" {
                return item
            }
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                if let subApp = try findAppBundle(in: item) {
                    return subApp
                }
            }
        }
        return nil
    }
    
    // MARK: - 原地安全替换并自动重启
    public func installAndRelaunch() {
        guard case let .readyToInstall(extractedAppURL) = state else { return }
        
        let currentBundleURL = Bundle.main.bundleURL
        
        // 安全检查：如果是在开发构建产物目录，则提示并安全处理
        if currentBundleURL.path.contains(".build/") || !currentBundleURL.path.hasSuffix(".app") {
            let alert = NSAlert()
            alert.messageText = "开发调试环境提示"
            alert.informativeText = "当前应用运行在开发编译目录，不支持自动原地替换。已为您打开新版本目录。"
            alert.addButton(withTitle: "好")
            alert.runModal()
            NSWorkspace.shared.selectFile(extractedAppURL.path, inFileViewerRootedAtPath: "")
            self.state = .idle
            self.isSheetPresented = false
            return
        }
        
        self.state = .installing
        
        let currentPid = ProcessInfo.processInfo.processIdentifier
        let targetAppPath = currentBundleURL.path
        let newAppPath = extractedAppURL.path
        
        // 编写极简的原地替换与自动重启脚本
        let script = """
        #!/bin/bash
        # 1. 等待当前进程安全退出
        while kill -0 \(currentPid) 2>/dev/null; do
            sleep 0.2
        done

        # 2. 原地替换旧版本
        rm -rf "\(targetAppPath)"
        mv "\(newAppPath)" "\(targetAppPath)"

        # 3. 移除隔离属性，防止系统拦截
        xattr -cr "\(targetAppPath)" 2>/dev/null || true

        # 4. 重新启动新版本应用
        open "\(targetAppPath)"
        """
        
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("itstime_relaunch_\(UUID().uuidString).sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            
            // 后台启动脚本
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptURL.path]
            try process.run()
            
            // 退出当前应用
            NSApplication.shared.terminate(nil)
        } catch {
            self.state = .error("启动更新脚本失败: \(error.localizedDescription)")
        }
    }
    
    public func reset() {
        self.state = .idle
        self.isSheetPresented = false
    }
}

// MARK: - 隔离的 URLSession 下载代理
private final class DownloadDelegateBridge: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: (Double) -> Void
    private let onFinished: (URL) -> Void
    private let onError: (Error) -> Void
    
    init(
        onProgress: @escaping (Double) -> Void,
        onFinished: @escaping (URL) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.onProgress = onProgress
        self.onFinished = onFinished
        self.onError = onError
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0.0), 1.0)
        onProgress(progress)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        onFinished(location)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as? URLError, error.code == .cancelled {
            return
        }
        if let error = error {
            onError(error)
        }
    }
}
