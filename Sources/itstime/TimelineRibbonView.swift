import SwiftUI
import AppKit

struct UpcomingTimelineEvent: Identifiable {
    var id: UUID { task.id }
    let task: ScheduleTask
    let triggerDate: Date
    let timeRemaining: TimeInterval
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: triggerDate)
    }
    
    var formattedCountdown: String {
        let secs = max(0, Int(timeRemaining))
        let m = secs / 60
        let s = secs % 60
        if m >= 60 {
            let h = m / 60
            return "\(h)小时\(m % 60)分后"
        } else if m > 0 {
            return "\(m)分\(s)秒后"
        } else {
            return "\(s)秒后"
        }
    }
}

struct TimelineRibbonView: View {
    @ObservedObject var scheduler = SchedulerEngine.shared
    
    // 时间带展示未来多长时间（默认未来 6 小时窗口，如果最近的在更后，自动扩展至 12 小时）
    @State private var hoveredEvent: UpcomingTimelineEvent? = nil
    
    // 计算未来即将发生的事件队列
    private var upcomingEvents: [UpcomingTimelineEvent] {
        let now = Date()
        var list: [UpcomingTimelineEvent] = []
        
        for task in scheduler.tasks where task.isEnabled && !task.isPaused {
            if let nextDate = task.calculateNextTriggerDate(from: now) {
                let diff = nextDate.timeIntervalSince(now)
                if diff > 0 {
                    list.append(UpcomingTimelineEvent(task: task, triggerDate: nextDate, timeRemaining: diff))
                }
            }
        }
        
        return list.sorted { $0.triggerDate < $1.triggerDate }
    }
    
    // 动态计算时间轴的总跨度（至少 2 小时，最长根据最近事件适配至 12 小时）
    private var timelineSpanSeconds: TimeInterval {
        guard let maxDiff = upcomingEvents.map({ $0.timeRemaining }).max() else {
            return 3600 * 2 // 默认 2 小时
        }
        if maxDiff <= 3600 * 2 {
            return 3600 * 2
        } else if maxDiff <= 3600 * 6 {
            return 3600 * 6
        } else {
            return min(3600 * 24, max(3600 * 12, maxDiff * 1.15))
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 时间带顶栏小标
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                    Text("时间流动轴 (未来 \(formatSpanTitle(timelineSpanSeconds)))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if upcomingEvents.isEmpty {
                    Text("暂无激活的定时事件")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.6))
                } else {
                    Text("即将发生 \(upcomingEvents.count) 个事件")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 4)
            
            // 时间轴轨道可视化区域
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let nowX: CGFloat = 36
                let endX: CGFloat = width - 36
                let usableWidth = max(50, endX - nowX)
                let trackY = height / 2 + 2
                
                ZStack(alignment: .leading) {
                    // 1. 基础导轨背景线
                    Path { p in
                        p.move(to: CGPoint(x: nowX, y: trackY))
                        p.addLine(to: CGPoint(x: endX, y: trackY))
                    }
                    .stroke(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.6), Color.white.opacity(0.12)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    
                    // 2. 左端起始点：“现在 (Now)”
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                            .shadow(color: Color.accentColor.opacity(0.8), radius: 4)
                        Text("当前")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.accentColor)
                    }
                    .position(x: nowX, y: trackY - 14)
                    
                    // 3. 右端点刻度
                    Text(formatSpanTitle(timelineSpanSeconds))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.6))
                        .position(x: endX, y: trackY - 14)
                    
                    // 4. 事件节点散布在时间轴上
                    ForEach(Array(upcomingEvents.enumerated()), id: \.element.id) { index, event in
                        let ratio = CGFloat(min(1.0, max(0.0, event.timeRemaining / timelineSpanSeconds)))
                        let posX = nowX + ratio * usableWidth
                        // 上下交替错落，防止文字标签重叠
                        let isAlt = index % 2 == 1
                        let nodeY = trackY + (isAlt ? 14 : -14)
                        
                        EventNodeView(
                            event: event,
                            isAlt: isAlt,
                            isHovered: hoveredEvent?.id == event.id,
                            onExecute: {
                                scheduler.executeAction(for: event.task)
                            }
                        )
                        .position(x: posX, y: nodeY)
                        .onHover { hover in
                            hoveredEvent = hover ? event : nil
                        }
                    }
                }
            }
            .frame(height: 58)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 12)
    }
    
    private func formatSpanTitle(_ span: TimeInterval) -> String {
        let hours = Int(span / 3600)
        return "\(hours) 小时"
    }
}

// MARK: - 单个事件时间节点
struct EventNodeView: View {
    let event: UpcomingTimelineEvent
    let isAlt: Bool
    let isHovered: Bool
    let onExecute: () -> Void
    
    var body: some View {
        VStack(spacing: 3) {
            if !isAlt {
                contentPill
                pinLine
            } else {
                pinLine
                contentPill
            }
        }
    }
    
    private var contentPill: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 9))
                .foregroundColor(iconColor)
            
            Text(event.formattedTime)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
            
            Text(event.task.name)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(isHovered ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.08))
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(isHovered ? Color.accentColor : Color.white.opacity(0.2), lineWidth: 0.8)
        )
        .shadow(color: isHovered ? Color.accentColor.opacity(0.3) : Color.black.opacity(0.06), radius: isHovered ? 6 : 2)
        .floatingTooltip("【\(event.task.name)】将于 \(event.formattedTime) (\(event.formattedCountdown)) 触发")
    }
    
    private var pinLine: some View {
        Rectangle()
            .fill(isHovered ? Color.accentColor : Color.white.opacity(0.3))
            .frame(width: 1, height: 6)
    }
    
    private var iconName: String {
        switch event.task.action {
        case .none: return "bell"
        case .popupContent: return "checklist"
        case .playLocalAudio: return "waveform"
        case .openURL: return "safari"
        }
    }
    
    private var iconColor: Color {
        switch event.task.action {
        case .none: return .orange
        case .popupContent: return .purple
        case .playLocalAudio: return .green
        case .openURL: return .blue
        }
    }
}
