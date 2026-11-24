import SwiftUI
import AppKit

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
    
    // MARK: - 日期导航栏（全区域可点、消除图标穿透、保留 ‹ ● ›）
    private var dateNavigationBar: some View {
        HStack(spacing: 4) {
            // 控制组：‹ ● ›（热区全面扩大至 28×26pt，带防穿透底色与 hover 确认反馈）
            HStack(spacing: 2) {
                // 上一周期 ‹
                ScreenTimeIconButton(
                    action: { tracker.goToPrevious() },
                    systemName: "chevron.left",
                    helpText: "上一周期",
                    width: 28,
                    height: 26
                )
                
                // 回到今日圆点 ●（视觉 6pt，点击热区 26×26pt，杜绝点偏）
                ScreenTimeIconButton(
                    action: { tracker.goToToday() },
                    customContent: AnyView(
                        Circle()
                            .fill(tracker.isCurrentPeriod ? Color.secondary.opacity(0.25) : Color.accentColor)
                            .frame(width: 6, height: 6)
                    ),
                    helpText: "回到今日",
                    isDisabled: tracker.isCurrentPeriod,
                    width: 26,
                    height: 26
                )
                
                // 下一周期 ›（未来禁用）
                ScreenTimeIconButton(
                    action: { tracker.goToNext() },
                    systemName: "chevron.right",
                    helpText: "下一周期",
                    isDisabled: !tracker.canGoNext,
                    width: 28,
                    height: 26
                )
            }
            
            Spacer()
            
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
            
            Spacer()
            
            // 右侧平衡占位，确保绝对居中对称
            HStack(spacing: 2) {
                Color.clear.frame(width: 28, height: 26)
                Color.clear.frame(width: 26, height: 26)
                Color.clear.frame(width: 28, height: 26)
            }
        }
    }
    
    // MARK: - 核心看板
    private var heroSection: some View {
        HStack(alignment: .lastTextBaseline) {
            // 大号时间数字
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(tracker.currentStats.formattedTotalDuration)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                if tracker.isUserIdle {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                        .help("闲置挂起中")
                } else if tracker.selectedScope == .day && tracker.isCurrentPeriod && tracker.isTrackingEnabled {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .help("统计中")
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
                                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.001))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
        }
    }
    
    // MARK: - 应用列表（纯净排版：图标 + 名称 + 时长 + 进度条）
    private var appListView: some View {
        let apps = tracker.currentStats.sortedApps
        return Group {
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
    
    // MARK: - 事件列表（铃铛 + 任务名 + 次数）
    private var eventListView: some View {
        let events = tracker.currentStats.sortedEventTriggers
        return Group {
            if events.isEmpty {
                emptyPlaceholder(systemImage: "bell.slash")
            } else {
                ForEach(events) { event in
                    HStack(spacing: 10) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.orange.opacity(0.12)))
                        
                        Text(event.taskName)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text("\(event.count)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.orange.opacity(0.12)))
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
        .help(helpText)
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
