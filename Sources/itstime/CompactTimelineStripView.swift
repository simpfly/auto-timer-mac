import SwiftUI
import AppKit

// MARK: - 时间带事件条目数据结构
public struct TimelineEventItem: Identifiable {
    public let id: String
    public let name: String
    public let date: Date
    public let kind: TimelineKind
    public let actionDesc: String
    
    public enum TimelineKind {
        case countdown
        case daily
        case interval
        case once
        case calendar
        
        public var title: String {
            switch self {
            case .countdown: return "倒计时"
            case .daily: return "定时"
            case .interval: return "循环"
            case .once: return "单次"
            case .calendar: return "日程"
            }
        }
        
        public var icon: String {
            switch self {
            case .countdown: return "timer"
            case .daily: return "clock.arrow.circlepath"
            case .interval: return "repeat"
            case .once: return "bell"
            case .calendar: return "calendar"
            }
        }
        
        public var color: Color {
            switch self {
            case .countdown: return .orange
            case .daily: return .indigo
            case .interval: return .teal
            case .once: return .orange
            case .calendar: return .purple
            }
        }
    }
}

// MARK: - 时间带运行模式
public enum TimelineStripMode {
    case upcoming // 主窗口：未来即将触发
    case past     // 统计窗口：现在之前已触发
}

// MARK: - 紧凑型横向时间轴带 (非等比标尺：全事件流式概览，类型专属色彩，高颜值悬浮气泡)
public struct CompactTimelineStripView: View {
    public var mode: TimelineStripMode
    
    @ObservedObject var scheduler = SchedulerEngine.shared
    @ObservedObject var eventKit = EventKitService.shared
    @ObservedObject var tracker = ScreenTimeTrackerService.shared
    
    // 定时刷新触发（每 1 秒刷新当前时间与倒数时分秒）
    @State private var currentDate: Date = Date()
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    // 当前悬浮的事件项与精确锚点 X 坐标
    @State private var hoveredEvent: TimelineEventItem? = nil
    @State private var hoveredX: CGFloat = 0
    
    public init(mode: TimelineStripMode = .upcoming) {
        self.mode = mode
    }
    
    // MARK: - 获取要展示的事件条目
    private var displayedEvents: [TimelineEventItem] {
        switch mode {
        case .upcoming:
            return upcomingEvents
        case .past:
            return pastEvents
        }
    }
    
    // MARK: - 获取所有即将到来的事件（不设死板窗口，各类事件按其类型提取与赋予颜色）
    private var upcomingEvents: [TimelineEventItem] {
        let now = currentDate
        var list: [TimelineEventItem] = []
        
        // 1. It's Time 内置任务
        for task in scheduler.tasks where task.isEnabled && !task.isPaused {
            if let nextDate = task.calculateNextTriggerDate(from: now), nextDate >= now {
                let kind: TimelineEventItem.TimelineKind
                switch task.trigger {
                case .countdown: kind = .countdown
                case .daily: kind = .daily
                case .interval: kind = .interval
                case .once: kind = .once
                }
                
                let desc = task.action.summary
                list.append(TimelineEventItem(
                    id: "task_\(task.id)",
                    name: task.name,
                    date: nextDate,
                    kind: kind,
                    actionDesc: desc
                ))
            }
        }
        
        // 2. 系统日历日程（若已授权，同步纳入；过滤掉全天日程及已导入为计划的任务，避免时间轴重复渲染）
        if eventKit.isCalendarAuthorized {
            for ev in eventKit.todayCalendarEvents {
                if !ev.isAllDay && ev.startDate >= now {
                    // 若已经被导入为应用内定时计划，以应用内计划为准，不重复展示
                    if !EventKitService.isCalendarEventImported(event: ev, tasks: scheduler.tasks) {
                        list.append(TimelineEventItem(
                            id: "cal_\(ev.id)",
                            name: ev.title,
                            date: ev.startDate,
                            kind: .calendar,
                            actionDesc: ev.location ?? "系统日历日程"
                        ))
                    }
                }
            }
        }
        
        // 按时间升序排序，取接下来最近的最多 4 个事件
        return Array(list.sorted { $0.date < $1.date }.prefix(4))
    }
    
    // MARK: - 获取现在之前已经触发过的事件
    private var pastEvents: [TimelineEventItem] {
        let now = currentDate
        let calendar = Calendar.current
        var list: [TimelineEventItem] = []
        var recordedIds = Set<String>()
        
        // 1. 从 ScreenTimeTrackerService 历史流水中提取
        let logs = tracker.currentStats.pastEventLogs
        for log in logs where log.timestamp <= now {
            let kind: TimelineEventItem.TimelineKind
            switch log.kindString {
            case "countdown": kind = .countdown
            case "daily": kind = .daily
            case "interval": kind = .interval
            case "once": kind = .once
            case "calendar": kind = .calendar
            default: kind = .once
            }
            let item = TimelineEventItem(
                id: "past_log_\(log.id)",
                name: log.taskName,
                date: log.timestamp,
                kind: kind,
                actionDesc: log.actionDesc
            )
            list.append(item)
            if let tId = log.taskId {
                recordedIds.insert("task_\(tId)")
            }
        }
        
        // 2. 兜底补全：若当前流水尚未包含某些已触发任务（如旧版本记录或今日已触发）
        for task in scheduler.tasks {
            if let lastDate = task.lastTriggeredAt, lastDate <= now && calendar.isDateInToday(lastDate) {
                let taskIdStr = "task_\(task.id)"
                if !recordedIds.contains(taskIdStr) {
                    let kind: TimelineEventItem.TimelineKind
                    switch task.trigger {
                    case .countdown: kind = .countdown
                    case .daily: kind = .daily
                    case .interval: kind = .interval
                    case .once: kind = .once
                    }
                    list.append(TimelineEventItem(
                        id: taskIdStr,
                        name: task.name,
                        date: lastDate,
                        kind: kind,
                        actionDesc: task.action.summary
                    ))
                    recordedIds.insert(taskIdStr)
                }
            }
        }
        
        // 3. 系统日历日程（今天已经开始或过去的日程）
        if eventKit.isCalendarAuthorized {
            for ev in eventKit.todayCalendarEvents {
                if !ev.isAllDay && ev.startDate < now {
                    if !EventKitService.isCalendarEventImported(event: ev, tasks: scheduler.tasks) {
                        list.append(TimelineEventItem(
                            id: "cal_past_\(ev.id)",
                            name: ev.title,
                            date: ev.startDate,
                            kind: .calendar,
                            actionDesc: ev.location ?? "系统日历日程"
                        ))
                    }
                }
            }
        }
        
        // 按时间升序排序，取最近触发的最多 4 个事件
        let sorted = list.sorted { $0.date < $1.date }
        return Array(sorted.suffix(4))
    }
    
    // MARK: - 大致间距符合真实时差的自适应排布算法（保序、时差大间距大、较远可清晰显示）
    private func computeRatios(for events: [TimelineEventItem], trackWidth: CGFloat) -> [CGFloat] {
        let count = events.count
        guard count > 0 else { return [] }
        
        let now = currentDate
        let minRatio: CGFloat = 0.20
        let maxRatio: CGFloat = 0.95
        let span = maxRatio - minRatio
        
        var ratios: [CGFloat] = []
        
        if mode == .upcoming {
            let deltas = events.map { max(10, $0.date.timeIntervalSince(now)) }
            guard let maxDelta = deltas.last else { return [] }
            
            if count == 1 {
                return [0.60]
            }
            
            ratios = deltas.map { delta in
                let frac = CGFloat(delta / maxDelta)
                return minRatio + frac * span
            }
        } else {
            // 过去事件：事件按时间由早到晚升序排列
            if count == 1 {
                return [0.55]
            }
            let firstDate = events.first!.date
            let totalSpan = max(60, events.last!.date.timeIntervalSince(firstDate))
            ratios = events.map { ev in
                let delta = max(0, ev.date.timeIntervalSince(firstDate))
                let frac = CGFloat(delta / totalSpan)
                return minRatio + frac * span
            }
        }
        
        // 最小防重叠间距保护（当两个事件距离极其接近时，保证至少 32pt 间距，不重叠）
        let minGap = max(0.12, 32.0 / max(50, trackWidth))
        for i in 1..<count {
            if ratios[i] - ratios[i - 1] < minGap {
                ratios[i] = ratios[i - 1] + minGap
            }
        }
        
        // 整体右边界保护（避免溢出）
        if let last = ratios.last, last > 1.0 {
            let overflow = last - 1.0
            for i in 0..<count {
                ratios[i] = max(minRatio, ratios[i] - overflow)
            }
        }
        
        return ratios
    }
    
    // 当前时间格式化（HH:mm）
    private var formattedCurrentTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: currentDate)
    }
    
    // MARK: - 格式化事件时间短标签
    private func formattedTime(for date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "HH:mm"
            return "昨 " + formatter.string(from: date)
        } else if calendar.isDateInTomorrow(date) {
            formatter.dateFormat = "HH:mm"
            return "明 " + formatter.string(from: date)
        } else {
            formatter.dateFormat = "M/d"
            return formatter.string(from: date)
        }
    }
    
    // MARK: - 格式化气泡内完整时间
    private func formattedFullTime(for date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "今天 HH:mm"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "昨天 HH:mm"
            return formatter.string(from: date)
        } else if calendar.isDateInTomorrow(date) {
            formatter.dateFormat = "明天 HH:mm"
            return formatter.string(from: date)
        } else {
            formatter.dateFormat = "M月d日 HH:mm"
            return formatter.string(from: date)
        }
    }
    
    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let padL: CGFloat = 16
            let padR: CGFloat = 22
            let trackW = max(30, w - padL - padR)
            let trackY: CGFloat = 7.5
            let textY: CGFloat = trackY + 12.5
            
            let events = displayedEvents
            let ratios = computeRatios(for: events, trackWidth: trackW)
            
            ZStack(alignment: .topLeading) {
                // 1. 底层微浅导轨线
                Path { p in
                    p.move(to: CGPoint(x: padL, y: trackY))
                    p.addLine(to: CGPoint(x: padL + trackW, y: trackY))
                }
                .stroke(Color.primary.opacity(0.12), lineWidth: 1.5)
                
                // 2. 当前起点标示（小圆点 + 下方实际时间/状态文本，严格垂直对齐，无偏移）
                Circle()
                    .fill(mode == .past ? Color.secondary.opacity(0.4) : Color.accentColor)
                    .frame(width: 4.5, height: 4.5)
                    .position(x: padL, y: trackY)
                
                Text(mode == .past ? "已发生" : formattedCurrentTime)
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.75))
                    .lineLimit(1)
                    .fixedSize()
                    .position(x: padL, y: textY)
                
                // 3. 动态非等比事件节点与时间标注
                if events.isEmpty {
                    Text(mode == .past ? "暂无已触发事件" : "暂无待办")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(.secondary.opacity(0.45))
                        .position(x: padL + trackW * 0.5, y: textY)
                } else {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, item in
                        let r = (index < ratios.count) ? ratios[index] : 0.5
                        let x = padL + min(1.0, max(0.15, r)) * trackW
                        
                        // 节点药丸：垂直中心精确落在导轨线 trackY 上（与起点小蓝点完全在同一水平线上）
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(item.kind.color)
                            .frame(width: 4.5, height: 8.5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 1.5)
                                    .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
                            )
                            .position(x: x, y: trackY)
                        
                        // 时间文本：严格居中于节点 X 坐标，高度基线与当前时间对齐
                        Text(formattedTime(for: item.date))
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(item.kind.color.opacity(0.85))
                            .lineLimit(1)
                            .fixedSize()
                            .position(x: x, y: textY)
                        
                        // 悬停交互热区（覆盖药丸与文字，杜绝断层闪烁）
                        Color.clear
                            .frame(width: 36, height: 25)
                            .contentShape(Rectangle())
                            .onHover { isHover in
                                if isHover {
                                    hoveredX = x
                                    hoveredEvent = item
                                } else if hoveredEvent?.id == item.id {
                                    hoveredEvent = nil
                                }
                            }
                            .position(x: x, y: trackY + 6)
                    }
                }
                
                // 4. 单一精准定位悬浮气泡锚点
                if let _ = hoveredEvent {
                    Color.clear
                        .frame(width: 4, height: 4)
                        .position(x: hoveredX, y: trackY + 14)
                        .allowsHitTesting(false)
                        .popover(item: $hoveredEvent, arrowEdge: .bottom) { currentItem in
                            EventTooltipBubbleView(item: currentItem)
                        }
                }
            }
        }
        .frame(height: 25)
        .onAppear {
            // 每次 Popover 展开时立即对齐真实当前时间，避免显示陈旧时刻
            currentDate = Date()
        }
        .onReceive(timer) { input in
            currentDate = input
        }
    }
}

// MARK: - 优质悬浮提示气泡卡片 UI（独立视图保证秒级实时跳动，足宽不截断）
struct EventTooltipBubbleView: View {
    let item: TimelineEventItem
    @State private var now: Date = Date()
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 顶栏：类型标签胶囊 + 倒计时剩余时长或已发生时长（足宽且固定尺寸，绝不截断）
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    Image(systemName: item.kind.icon)
                        .font(.system(size: 8))
                    Text(item.kind.title)
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(item.kind.color)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(item.kind.color.opacity(0.12))
                .clipShape(Capsule())
                
                Spacer()
                
                let diffSec = item.date.timeIntervalSince(now)
                Text(formattedRemainingCountdown(diffSec: diffSec))
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            
            // 任务或日程名称
            Text(item.name)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            // 底栏：触发时间与动作
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Text(formattedFullTime(for: item.date))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                
                if !item.actionDesc.isEmpty {
                    Text("·")
                        .foregroundColor(.secondary.opacity(0.4))
                    Text(item.actionDesc)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 195, maxWidth: 245)
        .onReceive(timer) { input in
            self.now = input
        }
    }
    
    // MARK: - 格式化倒计时剩余时分秒或已发生时间
    private func formattedRemainingCountdown(diffSec: TimeInterval) -> String {
        if diffSec < -1 {
            let pastSec = Int(abs(diffSec))
            let h = pastSec / 3600
            let m = (pastSec % 3600) / 60
            if h >= 24 {
                let days = h / 24
                return "\(days)天前"
            } else if h > 0 {
                return m > 0 ? "\(h)小时\(m)分前" : "\(h)小时前"
            } else if m > 0 {
                return "\(m)分钟前"
            } else {
                return "刚刚"
            }
        }
        
        let total = Int(max(0, diffSec))
        if total <= 0 { return "即将触发" }
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        
        if h > 0 {
            if m > 0 {
                return "还有 \(h)小时\(m)分"
            } else {
                return "还有 \(h)小时"
            }
        } else if m > 0 {
            if s > 0 {
                return "还有 \(m)分\(s)秒"
            } else {
                return "还有 \(m)分钟"
            }
        } else {
            return "还有 \(s)秒"
        }
    }
    
    // 格式化气泡内完整时间
    private func formattedFullTime(for date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "今天 HH:mm"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "昨天 HH:mm"
            return formatter.string(from: date)
        } else if calendar.isDateInTomorrow(date) {
            formatter.dateFormat = "明天 HH:mm"
            return formatter.string(from: date)
        } else {
            formatter.dateFormat = "M月d日 HH:mm"
            return formatter.string(from: date)
        }
    }
}
