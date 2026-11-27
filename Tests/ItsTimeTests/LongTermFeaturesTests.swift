import XCTest
@testable import itstime

@MainActor
final class LongTermFeaturesTests: XCTestCase {
    
    func testManagedAudioImportAndOrphanCleanup() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ItsTimeAudioTest_\(UUID().uuidString)", isDirectory: true)
        let sourceDir = tempRoot.appendingPathComponent("Source", isDirectory: true)
        let managedDir = tempRoot.appendingPathComponent("Managed", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: managedDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        
        let file1 = sourceDir.appendingPathComponent("bell.wav")
        let file2 = sourceDir.appendingPathComponent("chime.mp3")
        try Data("audio1".utf8).write(to: file1)
        try Data("audio2".utf8).write(to: file2)
        
        let imported1 = AudioService.importManagedAudio(from: file1, into: managedDir)
        let imported2 = AudioService.importManagedAudio(from: file2, into: managedDir)
        
        XCTAssertTrue(imported1.hasPrefix(managedDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported1))
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported2))
        
        // 已在托管目录中的文件再次导入应直接复用原路径
        let reimported1 = AudioService.importManagedAudio(from: URL(fileURLWithPath: imported1), into: managedDir)
        XCTAssertEqual(reimported1, imported1)
        
        // 删除 file2 的引用后，孤儿文件应被清理
        AudioService.cleanupOrphanedManagedAudio(referencedPaths: [imported1], in: managedDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported1))
        XCTAssertFalse(FileManager.default.fileExists(atPath: imported2))
    }
    
    func testAppPreferencesDndAndSettings() {
        let prefs = AppPreferences.shared
        let originalPreAlert = prefs.audioPreAlertSeconds
        let originalAvoidance = prefs.avoidanceEnabled
        let originalBehavior = prefs.avoidanceBehavior
        let originalDnd = prefs.dndUntil
        defer {
            prefs.audioPreAlertSeconds = originalPreAlert
            prefs.avoidanceEnabled = originalAvoidance
            prefs.avoidanceBehavior = originalBehavior
            prefs.dndUntil = originalDnd
        }
        
        let now = Date()
        prefs.enableDndForOneHour(from: now)
        XCTAssertTrue(prefs.isDndActive)
        XCTAssertNotNil(prefs.dndRemainingDescription)
        
        prefs.clearDnd()
        XCTAssertFalse(prefs.isDndActive)
        XCTAssertNil(prefs.dndRemainingDescription)
        
        prefs.enableDndUntilTomorrow(from: now)
        XCTAssertTrue(prefs.isDndActive)
        XCTAssertTrue((prefs.dndUntil ?? now) > now)
        
        prefs.audioPreAlertSeconds = 10
        prefs.avoidanceEnabled = true
        prefs.avoidanceBehavior = .silentNotification
        XCTAssertEqual(AppPreferences.shared.audioPreAlertSeconds, 10)
        XCTAssertEqual(AppPreferences.shared.avoidanceBehavior, .silentNotification)
    }
    
    func testDndSkipsTriggerInScheduler() {
        let prefs = AppPreferences.shared
        let originalDnd = prefs.dndUntil
        defer { prefs.dndUntil = originalDnd }
        
        let engine = SchedulerEngine()
        let task = ScheduleTask(
            name: "免打扰测试倒计时",
            trigger: .countdown(totalSeconds: 1),
            action: .none
        )
        engine.addTask(task)
        defer { engine.deleteTask(byId: task.id) }
        
        prefs.enableDndForOneHour()
        engine.onTick()
        
        let updated = engine.tasks.first { $0.id == task.id }
        XCTAssertEqual(updated?.effectiveTriggerCount ?? 0, 0)
    }
}
