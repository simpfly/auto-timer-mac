import XCTest
@testable import itstime

@MainActor
final class SchedulerEngineTests: XCTestCase {
    
    private var engine: SchedulerEngine!
    private var originalTasks: [ScheduleTask] = []
    
    override func setUp() async throws {
        try await super.setUp()
        engine = SchedulerEngine.shared
        originalTasks = engine.tasks
    }
    
    override func tearDown() async throws {
        engine.tasks = originalTasks
        try await super.tearDown()
    }
    
    // MARK: - 基础 CRUD 操作测试
    func testTaskCRUD() {
        let task = ScheduleTask(
            name: "测试专注任务",
            trigger: .countdown(totalSeconds: 1500),
            isEnabled: true
        )
        
        // 1. 添加任务
        engine.addTask(task)
        XCTAssertTrue(engine.tasks.contains { $0.id == task.id })
        
        // 2. 更新任务
        var updated = task
        updated.name = "已重命名的专注任务"
        engine.updateTask(updated)
        let found = engine.tasks.first { $0.id == task.id }
        XCTAssertEqual(found?.name, "已重命名的专注任务")
        
        // 3. 删除任务
        engine.deleteTask(byId: task.id)
        XCTAssertFalse(engine.tasks.contains { $0.id == task.id })
    }
    
    // MARK: - 倒计时暂停与重置测试
    func testCountdownPauseAndReset() {
        var task = ScheduleTask(
            name: "番茄钟",
            trigger: .countdown(totalSeconds: 1500),
            isEnabled: true,
            isPaused: false
        )
        task.countdownRemainingSeconds = 400
        engine.addTask(task)
        
        // 1. 切换暂停
        engine.toggleTaskPause(id: task.id)
        let paused = engine.tasks.first { $0.id == task.id }
        XCTAssertEqual(paused?.isPaused, true)
        
        // 2. 重置倒计时（应恢复初始总秒数，且自动解除暂停）
        engine.resetCountdown(id: task.id)
        let reset = engine.tasks.first { $0.id == task.id }
        XCTAssertEqual(reset?.countdownRemainingSeconds, 1500)
        XCTAssertEqual(reset?.isPaused, false)
        
        // 清理
        engine.deleteTask(byId: task.id)
    }
    
    // MARK: - 任务启用与停用切换测试
    func testToggleTaskEnabled() {
        let task = ScheduleTask(
            name: "定时眼保健操",
            trigger: .countdown(totalSeconds: 300),
            isEnabled: true
        )
        engine.addTask(task)
        
        // 停用
        engine.toggleTaskEnabled(id: task.id)
        let disabled = engine.tasks.first { $0.id == task.id }
        XCTAssertEqual(disabled?.isEnabled, false)
        
        // 重新启用
        engine.toggleTaskEnabled(id: task.id)
        let reenabled = engine.tasks.first { $0.id == task.id }
        XCTAssertEqual(reenabled?.isEnabled, true)
        XCTAssertEqual(reenabled?.countdownRemainingSeconds, 300)
        
        engine.deleteTask(byId: task.id)
    }
    
    // MARK: - 一键暂停所有任务 (togglePauseAll)
    func testTogglePauseAll() {
        let task1 = ScheduleTask(name: "T1", trigger: .countdown(totalSeconds: 300), isEnabled: true, isPaused: false)
        let task2 = ScheduleTask(name: "T2", trigger: .daily(hour: 10, minute: 0), isEnabled: true, isPaused: false)
        engine.tasks = [task1, task2]
        
        XCTAssertTrue(engine.hasActiveRunningTasks)
        
        // 第一次调用：全部暂停
        engine.togglePauseAll()
        XCTAssertFalse(engine.hasActiveRunningTasks)
        XCTAssertTrue(engine.tasks.allSatisfy { $0.isPaused })
        
        // 第二次调用：全部恢复
        engine.togglePauseAll()
        XCTAssertTrue(engine.hasActiveRunningTasks)
        XCTAssertTrue(engine.tasks.allSatisfy { !$0.isPaused })
    }
    
    func testTextCountdownWaitsThroughTicksAndWakeUntilConfirmed() {
        let task = ScheduleTask(name: "确认后重计时", trigger: .countdown(totalSeconds: 60),
                                action: .popupContent(mode: .textNotification(message: "休息")))
        engine.tasks = [task]
        XCTAssertTrue(engine.beginWaitingForTextConfirmation(taskID: task.id))
        engine.onTick()
        engine.onTick()
        engine.cleanMissedTasksAfterWake()
        XCTAssertEqual(engine.tasks[0].countdownRemainingSeconds, 0)
        XCTAssertEqual(engine.tasks[0].effectiveTriggerCount, 0)
        engine.confirmTextCountdown(taskID: task.id)
        XCTAssertEqual(engine.tasks[0].countdownRemainingSeconds, 60)
        engine.tasks[0].countdownRemainingSeconds = 59
        engine.confirmTextCountdown(taskID: task.id)
        XCTAssertEqual(engine.tasks[0].countdownRemainingSeconds, 59)
    }

    func testTextCountdownConfirmationPreservesPauseAndIsIndependent() {
        let first = ScheduleTask(name: "一", trigger: .countdown(totalSeconds: 60),
                                 action: .popupContent(mode: .textNotification(message: "一")))
        let second = ScheduleTask(name: "二", trigger: .countdown(totalSeconds: 120),
                                  action: .popupContent(mode: .textNotification(message: "二")))
        engine.tasks = [first, second]
        engine.beginWaitingForTextConfirmation(taskID: first.id)
        engine.beginWaitingForTextConfirmation(taskID: second.id)
        engine.toggleTaskPause(id: first.id)
        engine.confirmTextCountdown(taskID: first.id)
        XCTAssertTrue(engine.tasks[0].isPaused)
        XCTAssertEqual(engine.tasks[0].countdownRemainingSeconds, 60)
        XCTAssertEqual(engine.tasks[1].countdownRemainingSeconds, 0)
        engine.deleteTask(byId: second.id)
        engine.confirmTextCountdown(taskID: second.id)
        XCTAssertEqual(engine.tasks.count, 1)
    }

    // MARK: - 文本弹窗提示关闭测试
    func testDismissTextAlert() {
        engine.activeTextAlert = TextAlertItem(title: "提示", message: "该休息了")
        XCTAssertNotNil(engine.activeTextAlert)
        
        engine.dismissTextAlert()
        XCTAssertNil(engine.activeTextAlert)
    }
    
    // MARK: - 预设任务与平滑数据迁移测试
    func testDefaultPresetsAndMigration() {
        UserDefaults.standard.removeObject(forKey: "ItsTime_Tasks_Storage_Key")
        UserDefaults.standard.removeObject(forKey: "itstime_tasks_storage_v2")
        UserDefaults.standard.removeObject(forKey: "tasks_v1")
        UserDefaults.standard.removeObject(forKey: "autotimer_tasks_storage")
        engine.reloadTasks()
        let tasks = engine.tasks
        
        // 验证预设任务存在且命名符合最新规范
        let eyeTask = tasks.first { $0.name == "做眼保健操" }
        XCTAssertNotNil(eyeTask, "必须包含预设任务：做眼保健操")
        if let eyeTask {
            if case .interval(let sec) = eyeTask.trigger {
                XCTAssertEqual(sec, 45 * 60, "做眼保健操应为 45 分钟循环")
            } else {
                XCTFail("做眼保健操触发器应为 interval")
            }
        }
        
        let waterTask = tasks.first { $0.name == "喝杯水" }
        XCTAssertNotNil(waterTask, "必须包含预设任务：喝杯水")
        if let waterTask {
            if case .interval(let sec) = waterTask.trigger {
                XCTAssertEqual(sec, 30 * 60, "喝杯水应为 30 分钟循环")
            } else {
                XCTFail("喝杯水触发器应为 interval")
            }
            if case .popupContent(let mode) = waterTask.action {
                if case .textNotification(let msg) = mode {
                    XCTAssertFalse(msg.contains("起身远眺"), "绝不应包含未开放编辑的冗余长文本")
                }
            }
        }
        
        let baduanjinTask = tasks.first { $0.name == "八段锦" }
        XCTAssertNotNil(baduanjinTask, "必须包含预设任务：八段锦")
    }
}
