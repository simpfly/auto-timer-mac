import SwiftUI
import AppKit
import Charts

// MARK: - 屏幕时间与事件统计内联视图（极致极简排版：Let the layout do the explaining）
public struct ScreenTimeView: View {
    @ObservedObject var tracker = ScreenTimeTrackerService.shared
    
    public var onDismiss: (() -> Void)? = nil
    @State private var selectedTab: TabType = .apps
    @State private var showingClearConfirmation: Bool = false
    @State private var showingDatePicker: Bool = false
    
    public enum TabType: String, CaseIterable {
        case apps = "应用"
        case events = "事件"
    }
    
    public init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // 顶栏：导航与核心周期切换
            topBar
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            
            Divider()
                .opacity(0.18)
            
            // 日期导航条：左右翻页、直接选择与回到今天
            dateNavigationBar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            
            Divider()
                .opacity(0.12)
            
            // 英雄看板：时长大字与当前视图切换
            heroSection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            
            Divider()
                .opacity(0.15)
            
            // 历史事件时间带（仅日视图展示已触发的事件轨迹）
            if tracker.selectedScope == .day {
                CompactTimelineStripView(mode: .past)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                
                Divider()
                    .opacity(0.12)
            }
            
            // 列表主区域：清晰无冗余标签
            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    if selectedTab == .apps {
                        appListView
                    } else {
                        eventListView
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            
            Divider()
                .opacity(0.18)
            
            // 底栏：轻量极简操作
            bottomBar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 顶栏
    private var topBar: some View {
        HStack(spacing: 12) {
            if let onDismiss = onDismiss {
                ScreenTimeIconButton(
                    action: onDismiss,
                    systemName: "chevron.left",
                    helpText: "返回",
                    width: 28,
                    height: 28
                )
            }
            
            Text("屏幕时间")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.primary)
            
            Spacer()
            
            // 日 / 周 / 月 / 年 切换
            HStack(spacing: 2) {
                ForEach(TimeScope.allCases) { scope in
                    let isSelected = tracker.selectedScope == scope
                    Button(action: {
                        tracker.selectedScope = scope
                    }) {
                        Text(scope.rawValue)
                            .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                            .foregroundColor(isSelected ? .primary : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(isSelected ? Color.white.opacity(0.18) : Color.white.opacity(0.001))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.12)))
        }
    }
    
    // MARK: - 日期导航栏（‹ [日期] › 左右对称布局，移除中间圆点）
    private var dateNavigationBar: some View {
        HStack(spacing: 6) {
            Spacer()
            
            // 上一周期 ‹
            ScreenTimeIconButton(
                action: { tracker.goToPrevious() },
                systemName: "chevron.left",
                helpText: "上一周期",
                width: 28,
                height: 26
            )
            
            // 居中日期展示（全胶囊区域响应点击，杜绝仅点文本的缺陷）
            DateCapsuleButton(
                title: tracker.periodTitle,
                isClickable: tracker.selectedScope == .day
            ) {
                if tracker.selectedScope == .day {
                    showingDatePicker.toggle()
                }
            }
            .popover(isPresented: $showingDatePicker) {
                CompactCalendarPickerView(
                    selectedDate: Binding(
                        get: { tracker.anchorDate },
                        set: { tracker.selectDate($0) }
                    ),
                    onSelect: {
                        showingDatePicker = false
                    }
                )
            }
            
            // 下一周期 ›（未来禁用）
            ScreenTimeIconButton(
                action: { tracker.goToNext() },
                systemName: "chevron.right",
                helpText: "下一周期",
                isDisabled: !tracker.canGoNext,
                width: 28,
                height: 26
            )
            
            Spacer()
        }
    }
    
    // MARK: - 核心看板：大号亮屏总时长、状态指示与蓝灰双色比例时间带
    private var heroSection: some View {
        VStack(spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                // 大号亮屏总时间 + 状态胶囊
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(tracker.currentStats.formattedTotalScreenOnDuration)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    if tracker.selectedScope != .day && tracker.currentStats.totalScreenOnSeconds > 0 {
                        Text("日均 \(tracker.currentStats.formattedDailyAverage)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    if tracker.selectedScope == .day && tracker.isCurrentPeriod && tracker.isTrackingEnabled {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(tracker.isUserIdle ? Color.secondary : Color.blue)
                                .frame(width: 6, height: 6)
                            Text(tracker.isUserIdle ? "闲置" : "统计中")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(tracker.isUserIdle ? .secondary : .blue)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill((tracker.isUserIdle ? Color.secondary : Color.blue).opacity(0.12))
                        )
                    }
                }
                
                Spacer()
                
                // 应用 / 事件 分段切换
                HStack(spacing: 2) {
                    ForEach(TabType.allCases, id: \.self) { tab in
                        let isSelected = selectedTab == tab
                        Button(action: {
                            selectedTab = tab
                        }) {
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                .foregroundColor(isSelected ? .primary : .secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSelected ? Color.white.opacity(0.18) : Color.white.opacity(0.001))
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
            }
            
            // 蓝灰双色比例时间带：活跃 vs 亮屏闲置（右侧外置黑色触发次数）
            ScreenTimeProportionStrip(
                activeSeconds: tracker.currentStats.totalActiveSeconds,
                idleSeconds: tracker.currentStats.totalIdleSeconds,
                activeText: tracker.currentStats.formattedTotalDuration,
                idleText: tracker.currentStats.formattedTotalIdleDuration,
                eventTriggerCount: tracker.currentStats.totalEventTriggerCount
            )
        }
    }
    
    // MARK: - 应用列表（周/月/年顶部带条形统计图 + 应用排行）
    private var appListView: some View {
        let apps = tracker.currentStats.sortedApps
        let buckets = tracker.currentStats.buckets
        return Group {
            if tracker.selectedScope != .day && !buckets.isEmpty && tracker.currentStats.totalActiveSeconds > 0 {
                ScreenTimeBarChartCard(
                    scope: tracker.selectedScope,
                    buckets: buckets
                )
                .padding(.bottom, 4)
            }
            
            if apps.isEmpty {
                emptyPlaceholder(systemImage: "macwindow")
            } else {
                let maxDuration = apps.first?.durationSeconds ?? 1
                ForEach(apps) { app in
                    let progress = maxDuration > 0 ? (app.durationSeconds / maxDuration) : 0
                    
                    VStack(spacing: 5) {
                        HStack(spacing: 8) {
                            Image(nsImage: tracker.icon(for: app.bundleIdentifier))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            
                            Text(app.appName)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(app.formattedDuration)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary.opacity(0.85))
                        }
                        
                        // 纤细高对比度进度条（纯靠长度传达占比，无须冗余文字）
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.secondary.opacity(0.1))
                                    .frame(height: 3)
                                
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.accentColor.opacity(0.85))
                                    .frame(width: max(3, geo.size.width * CGFloat(progress)), height: 3)
                            }
                        }
                        .frame(height: 3)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.35))
                    )
                }
            }
        }
    }
    
    // MARK: - 事件列表（背景条形图着色 + 按类型匹配图标与颜色 + 次数）
    private var eventListView: some View {
        let events = tracker.currentStats.sortedEventTriggers
        let tasks = SchedulerEngine.shared.tasks
        return Group {
            if events.isEmpty {
                emptyPlaceholder(systemImage: "bell.slash")
            } else {
                let maxCount = max(1, events.first?.count ?? 1)
                ForEach(events) { event in
                    let ratio = CGFloat(event.count) / CGFloat(maxCount)
                    let kind = TimelineEventItem.TimelineKind.resolve(
                        taskId: event.id,
                        triggerTypeTitle: event.triggerTypeTitle,
                        tasks: tasks
                    )
                    
                    HStack(spacing: 10) {
                        Image(systemName: kind.icon)
                            .font(.system(size: 12))
                            .foregroundColor(kind.color)
                            .frame(width: 20, height: 20)
                        
                        Text(event.taskName)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text("\(event.count)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(kind.color)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Color(NSColor.controlBackgroundColor).opacity(0.35)
                                kind.color.opacity(0.15)
                                    .frame(width: max(4, geo.size.width * ratio))
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
    
    // MARK: - 底栏
    private var bottomBar: some View {
        HStack {
            Spacer()
            
            Button("清空记录") {
                showingClearConfirmation = true
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.secondary.opacity(0.8))
            .confirmationDialog("确定清空本期统计吗？", isPresented: $showingClearConfirmation) {
                Button("清空", role: .destructive) {
                    tracker.clearCurrentDateData()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }
    
    private func emptyPlaceholder(systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .foregroundColor(.secondary.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - 极简紧凑现代日历选择器（全单元格灵敏响应、无死角热区、严丝合缝）
struct CompactCalendarPickerView: View {
    @Binding var selectedDate: Date
    var onSelect: (() -> Void)? = nil
    
    @State private var displayMonth: Date
    private let calendar = Calendar.current
    
    init(selectedDate: Binding<Date>, onSelect: (() -> Void)? = nil) {
        self._selectedDate = selectedDate
        self.onSelect = onSelect
        self._displayMonth = State(initialValue: selectedDate.wrappedValue)
    }
    
    var body: some View {
        VStack(spacing: 6) {
            // 月份与 ‹ ● › 控制组
            headerView
            
            // 星期表头
            weekdayHeaderView
            
            // 日期网格
            daysGridView
        }
        .padding(10)
        .frame(width: 236)
    }
    
    // MARK: - 顶部月份与 ‹ ● › 控制组
    private var headerView: some View {
        HStack {
            Text(monthTitle)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.primary)
            
            Spacer()
            
            HStack(spacing: 2) {
                // 上一月 ‹（热区扩大至 24×22pt，防穿透）
                ScreenTimeIconButton(
                    action: prevMonth,
                    systemName: "chevron.left",
                    helpText: "上一月",
                    width: 24,
                    height: 22
                )
                
                // 回到今日圆点 ●（热区 22×22pt，视觉 6pt，杜绝点偏）
                ScreenTimeIconButton(
                    action: goToToday,
                    customContent: AnyView(
                        Circle()
                            .fill(isCurrentMonthToday ? Color.accentColor : Color.secondary.opacity(0.4))
                            .frame(width: 6, height: 6)
                    ),
                    helpText: "回到今日",
                    width: 22,
                    height: 22
                )
                
                // 下一月 ›（未来月份禁用）
                ScreenTimeIconButton(
                    action: nextMonth,
                    systemName: "chevron.right",
                    helpText: "下一月",
                    isDisabled: !canGoNextMonth,
                    width: 24,
                    height: 22
                )
            }
        }
        .padding(.horizontal, 2)
    }
    
    // MARK: - 星期表头
    private var weekdayHeaderView: some View {
        let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
        return HStack(spacing: 0) {
            ForEach(weekdays, id: \.self) { day in
                Text(day)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 2)
    }
    
    // MARK: - 日期网格（每个单元格全面铺满防穿透）
    private var daysGridView: some View {
        let days = generateDaysInMonth()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        
        return LazyVGrid(columns: columns, spacing: 3) {
            ForEach(days) { item in
                if let date = item.date {
                    CalendarDayCell(
                        date: date,
                        isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                        isToday: calendar.isDateInToday(date),
                        isFuture: calendar.startOfDay(for: date) > calendar.startOfDay(for: Date())
                    ) {
                        selectedDate = date
                        onSelect?()
                    }
                } else {
                    Text("")
                        .frame(height: 28)
                }
            }
        }
    }
    
    // MARK: - 辅助计算
    private var monthTitle: String {
        let df = DateFormatter()
        df.dateFormat = "yyyy年M月"
        return df.string(from: displayMonth)
    }
    
    private var canGoNextMonth: Bool {
        let now = Date()
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let displayMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayMonth)) ?? displayMonth
        return displayMonthStart < currentMonthStart
    }
    
    private var isCurrentMonthToday: Bool {
        calendar.isDate(selectedDate, inSameDayAs: Date())
    }
    
    private func prevMonth() {
        if let prev = calendar.date(byAdding: .month, value: -1, to: displayMonth) {
            displayMonth = prev
        }
    }
    
    private func nextMonth() {
        guard canGoNextMonth else { return }
        if let next = calendar.date(byAdding: .month, value: 1, to: displayMonth) {
            displayMonth = next
        }
    }
    
    private func goToToday() {
        let today = Date()
        selectedDate = today
        displayMonth = today
        onSelect?()
    }
    
    private struct DayItem: Identifiable {
        let id = UUID()
        let date: Date?
    }
    
    private func generateDaysInMonth() -> [DayItem] {
        let comps = calendar.dateComponents([.year, .month], from: displayMonth)
        guard let startOfMonth = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: startOfMonth) else {
            return []
        }
        
        let firstWeekday = calendar.component(.weekday, from: startOfMonth) // 1 是周日
        let leadingSpaces = firstWeekday - 1
        
        var items: [DayItem] = []
        for _ in 0..<leadingSpaces {
            items.append(DayItem(date: nil))
        }
        
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                items.append(DayItem(date: date))
            }
        }
        
        return items
    }
}

// MARK: - 高灵敏度日历单元格（全格铺满、防穿透底色、hover 确认）
private struct CalendarDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let isFuture: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    private let calendar = Calendar.current
    
    var body: some View {
        Button(action: {
            if !isFuture {
                onSelect()
            }
        }) {
            ZStack {
                // 关键防穿透背景：未选中时支持 hover 浅灰反馈
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered && !isFuture && !isSelected ? Color.secondary.opacity(0.12) : Color.white.opacity(0.001))
                
                if isSelected {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 24, height: 24)
                } else if isToday {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.7), lineWidth: 1.2)
                        .frame(width: 24, height: 24)
                }
                
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 11, weight: isSelected ? .bold : (isToday ? .semibold : .regular)))
                    .foregroundColor(
                        isSelected ? .white :
                        (isFuture ? Color.secondary.opacity(0.25) :
                        (isToday ? Color.accentColor : .primary))
                    )
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .onHover { isHovered = $0 }
    }
}

// MARK: - 高灵敏度图标按钮（解决 macOS 图标透明像素穿透导致点击失效的核心组件）
struct ScreenTimeIconButton: View {
    let action: () -> Void
    var systemName: String? = nil
    var customContent: AnyView? = nil
    var helpText: String = ""
    var isDisabled: Bool = false
    var width: CGFloat = 28
    var height: CGFloat = 26
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // 关键点：Color.white.opacity(0.001) 让整块区域具备物理图层，杜绝细图标线条边缘漏点！
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered && !isDisabled ? Color.secondary.opacity(0.12) : Color.white.opacity(0.001))
                
                if let systemName = systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isDisabled ? Color.secondary.opacity(0.25) : (isHovered ? .primary : .secondary))
                } else if let customContent = customContent {
                    customContent
                }
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .floatingTooltip(helpText)
    }
}

// MARK: - 周/月/年屏幕时间条形统计图
private struct ScreenTimeBarChartCard: View {
    let scope: TimeScope
    let buckets: [ScreenTimeBucket]
    
    @State private var hoveredBucketId: String? = nil
    
    private var maxSeconds: TimeInterval {
        buckets.map(\.durationSeconds).max() ?? 0
    }
    
    private var useMinutesUnit: Bool {
        maxSeconds < 3600
    }
    
    private func displayValue(for seconds: TimeInterval) -> Double {
        useMinutesUnit ? (seconds / 60.0) : (seconds / 3600.0)
    }
    
    private var hoveredBucket: ScreenTimeBucket? {
        guard let hoveredBucketId else { return nil }
        return buckets.first { $0.id == hoveredBucketId }
    }
    
    private var visibleAxisLabels: Set<String> {
        switch scope {
        case .week:
            return Set(buckets.map(\.label))
        case .month:
            return ["1", "8", "15", "22", "29"]
        case .year:
            return ["1月", "3月", "5月", "7月", "9月", "11月"]
        case .day:
            return []
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(chartTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let hovered = hoveredBucket {
                    Text("\(hovered.fullLabel) · \(hovered.formattedDuration)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                }
            }
            
            Chart(buckets) { bucket in
                let isHovered = hoveredBucketId == bucket.id
                let hasHover = hoveredBucketId != nil
                BarMark(
                    x: .value("时间", bucket.label),
                    y: .value(useMinutesUnit ? "分钟" : "小时", displayValue(for: bucket.durationSeconds)),
                    width: scope == .month ? .fixed(5) : .automatic
                )
                .cornerRadius(scope == .month ? 2 : 3)
                .foregroundStyle(
                    bucket.durationSeconds > 0
                    ? Color.accentColor.opacity(hasHover ? (isHovered ? 1.0 : 0.35) : 0.85)
                    : Color.secondary.opacity(0.12)
                )
            }
            .chartXAxis {
                AxisMarks(values: buckets.map(\.label)) { value in
                    if let label = value.as(String.self), visibleAxisLabels.contains(label) {
                        AxisValueLabel {
                            Text(label)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        .foregroundStyle(Color.secondary.opacity(0.18))
                    AxisValueLabel {
                        if let num = value.as(Double.self) {
                            Text(formatAxisValue(num))
                                .font(.system(size: 9, design: .rounded))
                                .foregroundColor(.secondary.opacity(0.75))
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let plotOriginX = geo[proxy.plotAreaFrame].origin.x
                                let xPos = location.x - plotOriginX
                                if let label: String = proxy.value(atX: xPos),
                                   let matched = buckets.first(where: { $0.label == label }) {
                                    hoveredBucketId = matched.id
                                }
                            case .ended:
                                hoveredBucketId = nil
                            }
                        }
                }
            }
            .frame(height: 112)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.35))
        )
    }
    
    private var chartTitle: String {
        switch scope {
        case .week: return "每日趋势"
        case .month: return "本月趋势"
        case .year: return "月度趋势"
        case .day: return ""
        }
    }
    
    private func formatAxisValue(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        if useMinutesUnit {
            return "\(rounded)m"
        } else {
            return "\(rounded)h"
        }
    }
}

// MARK: - 蓝灰双色比例时间带（活跃 vs 亮屏闲置，外置黑色触发次数）
struct ScreenTimeProportionStrip: View {
    let activeSeconds: TimeInterval
    let idleSeconds: TimeInterval
    let activeText: String
    let idleText: String
    var eventTriggerCount: Int = 0
    
    private var showIdleBox: Bool {
        idleSeconds >= 60
    }
    
    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                let gap: CGFloat = showIdleBox ? 4 : 0
                let usableWidth = max(0, geo.size.width - gap)
                
                let total = max(1, activeSeconds + (showIdleBox ? idleSeconds : 0))
                let rawActiveRatio = CGFloat(activeSeconds / total)
                let minBoxWidth: CGFloat = min(68, usableWidth * 0.38)
                
                let activeWidth: CGFloat = {
                    guard showIdleBox else { return usableWidth }
                    let proposed = usableWidth * rawActiveRatio
                    return min(usableWidth - minBoxWidth, max(minBoxWidth, proposed))
                }()
                let idleWidth = max(0, usableWidth - activeWidth)
                
                HStack(spacing: gap) {
                    // 左方框：活跃时间（蓝色）
                    proportionBox(
                        title: "活跃",
                        durationText: activeText,
                        width: activeWidth,
                        tint: .blue,
                        helpText: "活跃时间 \(activeText)"
                    )
                    
                    // 右方框：亮屏闲置时间（灰色）
                    if showIdleBox {
                        proportionBox(
                            title: "闲置",
                            durationText: idleText,
                            width: idleWidth,
                            tint: .secondary,
                            helpText: "亮屏未活跃时间 \(idleText)"
                        )
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            }
            .frame(height: 26)
            
            if eventTriggerCount > 0 {
                Text("\(eventTriggerCount)次")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .fixedSize()
                    .floatingTooltip("事件触发 \(eventTriggerCount) 次")
            }
        }
    }
    
    @ViewBuilder
    private func proportionBox(
        title: String,
        durationText: String,
        width: CGFloat,
        tint: Color,
        helpText: String
    ) -> some View {
        // 根据时长文本长度预留足够空间，确保数字绝不被截断
        let estimatedDurationWidth = CGFloat(durationText.count) * 7.2 + 20
        let showTitle = width >= (estimatedDurationWidth + 36)
        HStack(spacing: 4) {
            if showTitle {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 2)
            }
            Text(durationText)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundColor(tint == .blue ? .blue : .secondary)
        .padding(.horizontal, 10)
        .frame(width: width, height: 26)
        .background(
            RoundedRectangle(cornerRadius: 6.5)
                .fill(tint.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 6.5)
                        .strokeBorder(tint.opacity(0.24), lineWidth: 0.75)
                )
        )
        .floatingTooltip(helpText)
    }
}

// MARK: - 高灵敏度日期胶囊按钮
private struct DateCapsuleButton: View {
    let title: String
    var isClickable: Bool = true
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered && isClickable ? Color.secondary.opacity(0.14) : Color.secondary.opacity(0.08))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isClickable)
        .onHover { isHovered = $0 }
    }
}
