import SwiftUI
import AppKit

// MARK: - 弧线形状（从当前分针顺时针扫至下个事件，直观展现剩余时间跨度）
struct ClockArcShape: Shape {
    var startDegrees: Double
    var sweepDegrees: Double
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        
        let startAngle = Angle.degrees(startDegrees - 90)
        let endAngle = Angle.degrees(startDegrees - 90 + sweepDegrees)
        
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}

// MARK: - 已排程事件视图模型
struct ScheduledEventItem: Identifiable {
    var id: UUID { task.id }
    let task: ScheduleTask
    let triggerDate: Date
    let timeRemaining: TimeInterval
    
    var formattedTargetTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: triggerDate)
    }
    
    var formattedDelta: String {
        let totalSeconds = max(0, Int(timeRemaining))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        
        if hours > 0 {
            if minutes > 0 {
                return "\(hours)小时\(minutes)分钟后"
            } else {
                return "\(hours)小时后"
            }
        } else if minutes > 0 {
            return "\(minutes)分钟后"
        } else {
            return "即将触发"
        }
    }
}

// MARK: - 沉静毛玻璃时钟展台
struct ClockVisualizerView: View {
    @ObservedObject var scheduler = SchedulerEngine.shared
    @State private var currentDate = Date()
    
    @State private var target: Date?
    @State private var editingID: UUID?
    @State private var hourText = ""
    @State private var minuteText = ""
    @State private var afternoon = false
    private enum TimeField: Hashable { case hour, minute }
    @FocusState private var focus: TimeField?
    var compact: Bool = true
    
    // 平稳温和的定时器，更新分钟与时刻
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    // 获取最近待执行的启用任务
    private var nextEvent: ScheduledEventItem? {
        let now = currentDate
        var activeEvents: [ScheduledEventItem] = []
        for task in scheduler.tasks where task.isEnabled && !task.isPaused {
            if let nextDate = task.calculateNextTriggerDate(from: now) {
                let diff = nextDate.timeIntervalSince(now)
                if diff > 0 {
                    activeEvents.append(ScheduledEventItem(task: task, triggerDate: nextDate, timeRemaining: diff))
                }
            }
        }
        return activeEvents.sorted { $0.triggerDate < $1.triggerDate }.first
    }
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(editingID == nil ? "新增任务" : "编辑任务").font(.headline)
                Spacer()
                Text(currentDateString).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                ForEach([false, true], id: \.self) { pm in
                    Button(pm ? "PM" : "AM") {
                        beginDraft()
                        afternoon = pm
                        updateTime()
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .foregroundStyle((target == nil ? isPM(currentDate.addingTimeInterval(60)) : afternoon) == pm ? Color.orange : Color.secondary)
                }
            }
            HStack(spacing: 6) {
                timeField(.hour)
                Text(":").foregroundStyle(.secondary)
                timeField(.minute)
            }
            clockDialView
                .frame(width: compact ? 104 : 156, height: compact ? 104 : 156)
            if let target {
                Text(validTime ? target.formatted(.relative(presentation: .named, unitsStyle: .wide)) + " · " + target.formatted(date: .abbreviated, time: .shortened) : "小时填 1 至 12，分钟填 0 至 59")
                    .font(.caption).foregroundStyle(.secondary)
                TaskEditorSheet(editingTask: scheduler.tasks.first { $0.id == editingID },
                                inlineDate: target, validTime: validTime,
                                onCancelInline: closeEditor) { task in
                    if editingID == nil { scheduler.addTask(task) }
                    else { scheduler.updateTask(task) }
                    closeEditor()
                }
                .id(editingID)
                if let editingID {
                    Button("删除任务", role: .destructive) {
                        scheduler.deleteTask(byId: editingID)
                        closeEditor()
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .font(.caption)
                }
            } else {
                Button("新增任务") { beginDraft(); focus = .hour }
                    .buttonStyle(.bordered)
                    .focusable(false)
                if let next = nextEvent {
                    Text("下个任务：" + next.task.name + " · " + next.formattedDelta)
                        .lineLimit(1).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .disableFocusEffect()
        .onChange(of: focus) { field in
            if field != nil { beginDraft() }
        }
        .padding(.horizontal, compact ? 14 : 22)
        .padding(.vertical, compact ? 12 : 18)
        .glassCard(cornerRadius: 14)
        .onReceive(timer) { input in
            currentDate = input
        }
    }
    
    // MARK: - 左侧表盘组件（严格几何同心）
    private var clockDialView: some View {
        ZStack {
            let clockDiameter: CGFloat = compact ? 104 : 156
            let radius = clockDiameter / 2
            let arcRadius = radius - (compact ? 10 : 14)
            
            // 1. 表盘外圈毛玻璃底座
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: clockDiameter, height: clockDiameter)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
            
            // 2. 表盘刻度线（以全容器正中心为锚点对称分布，绝对同心）
            ForEach(0..<60) { i in
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(i % 5 == 0 ? Color.primary.opacity(0.6) : Color.secondary.opacity(0.25))
                        .frame(width: i % 5 == 0 ? 2 : 1, height: i % 5 == 0 ? 7 : 4)
                    Spacer()
                }
                .frame(width: clockDiameter, height: clockDiameter)
                .rotationEffect(.degrees(Double(i) * 6))
            }
            
            // 3. 宁静的时间跨度弧环（若有下一个事件，展示分针距触发时刻的弧线）
            if let target {
                ClockArcShape(startDegrees: getCurrentMinuteAngle(), sweepDegrees: min(360, max(0, target.timeIntervalSince(currentDate) / 10)))
                    .stroke(.orange.opacity(0.8), lineWidth: 3)
                    .frame(width: arcRadius * 2, height: arcRadius * 2)
            } else if let next = nextEvent {
                let currentMinuteAngle = getCurrentMinuteAngle()
                let remainingSec = next.timeRemaining
                let sweepDegrees = min(360.0, max(3.0, (remainingSec / 3600.0) * 360.0))
                
                ClockArcShape(startDegrees: currentMinuteAngle, sweepDegrees: sweepDegrees)
                    .stroke(
                        Color.accentColor.opacity(0.4),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: arcRadius * 2, height: arcRadius * 2)
            }
            
            // 4. 时针与分针（采用上下对称虚拟占位法，旋转轴心天然严格锁定在正中心 (0, 0)）
            clockHands(radius: radius)
            
            // 5. 轴心金属微圆点（精准居中）
            Circle()
                .fill(Color.primary.opacity(0.85))
                .frame(width: 7, height: 7)
            
            Circle()
                .fill(Color.white)
                .frame(width: 2.5, height: 2.5)
            
            dialControls(radius: radius)

        }
    }
    
    private var remindersByMinute: [Int: [ScheduleTask]] {
        var groups: [Int: [ScheduleTask]] = [:]
        for task in scheduler.tasks where task.isEnabled && !task.isPaused {
            if case .once(let date) = task.trigger {
                groups[Calendar.current.component(.minute, from: date), default: []].append(task)
            }
        }
        return groups
    }

    @ViewBuilder
    private func dialControls(radius: CGFloat) -> some View {
        Circle().fill(Color.clear)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let dx = value.location.x - radius
                let dy = value.location.y - radius
                let startRadius = hypot(value.startLocation.x - radius, value.startLocation.y - radius)
                guard startRadius > radius * 0.15 else { return }
                if startRadius < radius * 0.58 {
                    beginDraft()
                    let hour = (Int((atan2(dx, -dy) * 6 / .pi).rounded()) + 12) % 12
                    hourText = String(format: "%02d", hour == 0 ? 12 : hour)
                    updateTime()
                    return
                }
                let minute = (Int((atan2(dx, -dy) * 30 / .pi).rounded()) + 60) % 60
                let calendar = Calendar.current
                let now = Date()
                if let previous = target {
                    let oldMinute = calendar.component(.minute, from: previous)
                    let delta = (minute - oldMinute + 90) % 60 - 30
                    if let proposed = calendar.date(byAdding: .minute, value: delta, to: previous), proposed > now {
                        select(proposed)
                    } else {
                        if let date = calendar.nextDate(after: now, matching: DateComponents(minute: minute, second: 0), matchingPolicy: .nextTime) { select(date) }
                    }
                } else {
                    if let date = calendar.nextDate(after: now, matching: DateComponents(minute: minute, second: 0), matchingPolicy: .nextTime) { select(date) }
                }
            })
            .help("点击或拖动刻度设置任务时间")

        if let target {
            let minute = Calendar.current.component(.minute, from: target)
            Circle().fill(.orange).frame(width: 10, height: 10)
                .position(markerPoint(minute, radius)).allowsHitTesting(false)
        } else {
            let groups = remindersByMinute
            ForEach(groups.keys.sorted(), id: \.self) { minute in
                if let tasks = groups[minute], let first = tasks.first {
                    if tasks.count == 1 {
                        Button { edit(first) } label: { marker }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .accessibilityLabel(first.trigger.displayTitle)
                            .help(first.trigger.displayTitle)
                            .position(markerPoint(minute, radius))
                    } else {
                        Menu {
                            ForEach(tasks) { task in
                                Button(task.trigger.displayTitle) { edit(task) }
                            }
                        } label: { marker }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden)
                        .focusable(false)
                        .frame(width: 16).position(markerPoint(minute, radius))
                    }
                }
            }

        }
    }

    private var marker: some View {
        Circle().fill(.orange).frame(width: 9, height: 9)
            .frame(width: 16, height: 16).contentShape(Circle())
    }

    private func markerPoint(_ minute: Int, _ radius: CGFloat) -> CGPoint {
        let angle = Double(minute) * .pi / 30
        let track = radius - (compact ? 10 : 14)
        return CGPoint(x: radius + sin(angle) * track, y: radius - cos(angle) * track)
    }

    private func isPM(_ date: Date) -> Bool {
        Calendar.current.component(.hour, from: date) >= 12
    }

    private func digits(_ field: TimeField, at date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date) % 12
        let number = field == .hour ? (hour == 0 ? 12 : hour) : calendar.component(.minute, from: date)
        return String(format: "%02d", number)
    }

    private func timeField(_ field: TimeField) -> some View {
        let label = field == .hour ? "小时" : "分钟"
        return TextField(label, text: Binding(get: {
            if target == nil { return digits(field, at: currentDate.addingTimeInterval(60)) }
            return field == .hour ? hourText : minuteText
        }, set: { value in
            beginDraft()
            if field == .hour { hourText = value } else { minuteText = value }
            updateTime()
        }))
        .focused($focus, equals: field)
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.center)
        .font(.system(size: 22, weight: .medium, design: .rounded))
        .monospacedDigit().frame(width: 54)
        .accessibilityLabel(label)
    }

    private var validTime: Bool {
        guard let hour = Int(hourText), let minute = Int(minuteText) else { return false }
        return (1...12).contains(hour) && (0...59).contains(minute)
    }

    private func updateTime() {
        guard validTime, let hour = Int(hourText), let minute = Int(minuteText) else { return }
        let time = DateComponents(hour: hour % 12 + (afternoon ? 12 : 0), minute: minute, second: 0)
        let now = Date()
        let start = editingID.flatMap { id in scheduler.tasks.first { $0.id == id } }
            .flatMap { task -> Date? in
                guard case .once(let date) = task.trigger else { return nil }
                return Calendar.current.startOfDay(for: date).addingTimeInterval(-1)
            }
        target = Calendar.current.nextDate(after: max(now, start ?? now), matching: time, matchingPolicy: .nextTime)
    }

    private func select(_ date: Date) {
        target = date
        hourText = digits(.hour, at: date)
        minuteText = digits(.minute, at: date)
        afternoon = isPM(date)
    }

    private func beginDraft() {
        guard target == nil else { return }
        let now = Date()
        if let nextMinute = Calendar.current.nextDate(after: now, matching: DateComponents(second: 0), matchingPolicy: .nextTime) {
            select(nextMinute)
        }
    }

    private func edit(_ task: ScheduleTask) {
        guard case .once(let date) = task.trigger else { return }
        editingID = task.id
        select(date)
    }

    private func closeEditor() {
        focus = nil
        editingID = nil
        target = nil
    }

    // MARK: - 几何同心时分指针（无秒针，平稳专注）
    @ViewBuilder
    private func clockHands(radius: CGFloat) -> some View {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.hour, .minute, .second], from: target ?? currentDate)
        let s = Double(comps.second ?? 0)
        let m = Double(comps.minute ?? 0) + s / 60.0
        let h = Double((comps.hour ?? 0) % 12) + m / 60.0
        
        let hourAngle = h * 30.0
        let minuteAngle = m * 6.0
        
        let hourLength = radius * 0.52
        let minuteLength = radius * 0.74
        
        // 时针：上半部实体，下半部等长透明占位，几何中心严格等于旋转原点
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.primary.opacity(0.85))
                .frame(width: 3.5, height: hourLength)
            Color.clear
                .frame(width: 3.5, height: hourLength)
        }
        .frame(width: 3.5, height: hourLength * 2)
        .rotationEffect(.degrees(hourAngle))
        
        // 分针：同理，严格同心旋转
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.primary.opacity(0.75))
                .frame(width: 2.2, height: minuteLength)
            Color.clear
                .frame(width: 2.2, height: minuteLength)
        }
        .frame(width: 2.2, height: minuteLength * 2)
        .rotationEffect(.degrees(minuteAngle))
    }
    
    // MARK: - 辅助计算与格式化
    private func getCurrentMinuteAngle() -> Double {
        let comps = Calendar.current.dateComponents([.minute, .second], from: currentDate)
        let s = Double(comps.second ?? 0)
        let m = Double(comps.minute ?? 0) + s / 60.0
        return m * 6.0
    }
    
    private var currentDateString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: currentDate)
    }
    
}
