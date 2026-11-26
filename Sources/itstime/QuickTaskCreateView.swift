import SwiftUI
import AppKit

// MARK: - 触发模式枚举
enum TriggerMode: Int, CaseIterable, Identifiable {
    case daily = 0
    case interval = 1
    case countdown = 2
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .daily: return "定时"
        case .interval: return "循环"
        case .countdown: return "倒计时"
        }
    }
    
    var icon: String {
        switch self {
        case .daily: return "clock.arrow.circlepath"
        case .interval: return "repeat"
        case .countdown: return "timer"
        }
    }
}

// MARK: - 动作类型枚举（四种正交提醒方式）
enum TaskActionKind: Int, CaseIterable, Identifiable {
    case textNotification = 0   // 文本提示（到期弹出毛玻璃大字卡片）
    case soundOnly = 1          // 声音通知（到期仅播放一声清脆铃声，不弹窗）
    case playAudio = 2          // 播放音频（播放眼保健操、八段锦或本地音频）
    case openURL = 3            // 打开链接（自动打开网页链接）
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .textNotification: return "文本提示"
        case .soundOnly: return "声音通知"
        case .playAudio: return "播放音频"
        case .openURL: return "打开链接"
        }
    }
    
    var icon: String {
        switch self {
        case .textNotification: return "text.bubble"
        case .soundOnly: return "bell"
        case .playAudio: return "waveform"
        case .openURL: return "safari"
        }
    }
}

// MARK: - 全功能快捷新增/就地编辑面板（全内联，零弹窗）
struct QuickTaskCreateView: View {
    @ObservedObject var scheduler = SchedulerEngine.shared
    @ObservedObject var audioService = AudioService.shared
    @ObservedObject var eventKit = EventKitService.shared
    
    // 支持就地编辑外部任务
    @Binding var editingTask: ScheduleTask?
    
    // 时间带宽度
    public var timelineWidth: CGFloat
    
    // 基本状态
    @State private var taskTitle: String = ""
    @State private var selectedMode: TriggerMode = .daily
    
    // 倒计时参数 (支持分与秒)
    @State private var countdownMinutes: Int = 25
    @State private var countdownSeconds: Int = 0
    @State private var countdownTimeString: String = "25:00"
    
    // 每天定时参数
    @State private var dailyTime: Date = {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 9
        comps.minute = 30
        return Calendar.current.date(from: comps) ?? Date()
    }()
    @State private var dailyTimeString: String = "09:30"
    
    // 循环间隔参数 (支持分与秒)
    @State private var intervalMinutes: Int = 30
    @State private var intervalSeconds: Int = 0
    @State private var intervalTimeString: String = "30:00"
    
    // 提醒方式（默认文本提示）
    @State private var actionKind: TaskActionKind = .textNotification
    @State private var isActionPickerExpanded: Bool = false
    @State private var hoveredActionKind: TaskActionKind? = nil
    
    // 音频参数
    @State private var selectedAudioName: String = "眼保健操"
    @State private var selectedAudioPath: String = "Resources/Audio/眼保健操.mp3"
    @State private var audioVolume: Double = 0.8
    @State private var inlineToast: String? = nil
    
    // 音频文件是否丢失判定
    private var isAudioFileMissing: Bool {
        guard actionKind == .playAudio else { return false }
        if selectedAudioPath == "内置水滴提示音" { return false }
        return AudioService.resolveAudioURL(for: selectedAudioPath) == nil
    }
    
    // 当前音频是否正在播放（由 AudioService 真实状态驱动）
    private var isCurrentAudioPlaying: Bool {
        return audioService.isPlaying && (audioService.currentPlayingName == selectedAudioName || audioService.currentPlayingName.contains(selectedAudioName))
    }
    
    // 打开链接参数
    @State private var targetURLString: String = "https://"
    
    // 自然语言时间识别结果
    @State private var parsedTimeResult: ParsedTimeResult? = nil
    
    // 焦点控制
    @FocusState private var isTitleFocused: Bool
    
    // 联想搜索
    @State private var isShowingSuggestions: Bool = false
    
    private var searchResults: [EventKitSearchResult] {
        guard isShowingSuggestions else { return [] }
        return eventKit.search(query: taskTitle)
    }
    
    public init(editingTask: Binding<ScheduleTask?> = .constant(nil), timelineWidth: CGFloat = 200) {
        self._editingTask = editingTask
        self.timelineWidth = timelineWidth
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 0. 顶部栏：提醒动作类型选择器（方案 B 替代静态“快捷创建”标题）+ 紧凑时间流动带
            HStack(alignment: .center) {
                actionKindPicker
                Spacer()
                CompactTimelineStripView()
                    .frame(width: timelineWidth)
            }
            .zIndex(100)
            
            // 1. 创建面板主卡片
            VStack(alignment: .leading, spacing: 10) {
                // 主输入行：名称输入 + 开始/保存按钮 + 取消按钮（绝对居中对齐，统一 30pt 基准高度）
                HStack(alignment: .center, spacing: 8) {
                    // 任务名称输入框（支持多行弹性展开，文本右侧强制安全避让，彻底杜绝右侧文字被遮挡）
                    ZStack(alignment: .topTrailing) {
                        TextField(defaultPlaceholder, text: $taskTitle, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .lineLimit(1...5)
                            .focused($isTitleFocused)
                            .disabled(isActionPickerExpanded)
                            .padding(.trailing, taskTitle.isEmpty ? 0 : 20)
                            .onChange(of: taskTitle) { val in
                                handleTaskTitleChange(val)
                            }
                            .onSubmit {
                                submitTask()
                            }
                        
                        if !taskTitle.isEmpty {
                            Button(action: {
                                taskTitle = ""
                                parsedTimeResult = nil
                                isShowingSuggestions = false
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 1.5)
                            .padding(.trailing, 1)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 30)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.8)
                    )
                    
                    // 开始 / 保存按钮 (纯图标极简呈现，不占横向空间，统一 30x30 尺寸防挤压)
                    Button(action: submitTask) {
                        Image(systemName: editingTask != nil ? "checkmark" : "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .floatingTooltip(editingTask != nil ? "保存修改" : "立即创建并启动")
                    
                    // 若处于就地编辑模式，展示取消按钮 (纯图标极简呈现，统一 30x30 尺寸)
                    if editingTask != nil {
                        Button(action: cancelEdit) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                                .frame(width: 30, height: 30)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .floatingTooltip("取消修改")
                    }
                }
            
            // 自然语言识别反馈胶囊
            if let parsed = parsedTimeResult {
                naturalLanguageHintBar(parsed: parsed)
            }
            
            // 2. 模式切换标签行
            HStack(spacing: 6) {
                ForEach(TriggerMode.allCases) { mode in
                    let isSelected = selectedMode == mode
                    Button(action: {
                        selectedMode = mode
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 10))
                            Text(mode.title)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        }
                        .foregroundColor(isSelected ? .white : .primary.opacity(0.8))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            
            // 3. 对应模式的时间选择器（左侧快捷预设胶囊，右侧统一时间调节器）
            durationAdjustmentView
                .padding(.top, 2)
            
            // 3. 动态内联设置区（当提醒方式为音频或链接时平滑展开，文本提示与声音通知均零展开）
            if actionKind == .playAudio || actionKind == .openURL {
                inlineActionConfigView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // 4. 轻量内联提示（如音频丢失等，显示 3 秒）
            if let toast = inlineToast {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text(toast)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.regularMaterial)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.orange.opacity(0.3), lineWidth: 0.8))
                .shadow(radius: 4)
                .transition(.opacity)
            }
            
            // 4. 日程与待办搜索联想浮层
            if !searchResults.isEmpty {
                suggestionResultsView
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(editingTask != nil ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: editingTask != nil ? 1.2 : 0.8)
        )
    }
    .onAppear {
            eventKit.checkPermissions()
            countdownTimeString = String(format: "%02d:%02d", countdownMinutes, countdownSeconds)
            dailyTimeString = formattedDailyTime
            intervalTimeString = String(format: "%02d:%02d", intervalMinutes, intervalSeconds)
            loadEditingTaskIfNeeded()
            if let draft = eventKit.prefilledDraft {
                applyPrefilledDraft(draft)
                eventKit.prefilledDraft = nil
            }
        }
        .onChange(of: eventKit.prefilledDraft) { draft in
            if let draft = draft {
                applyPrefilledDraft(draft)
                eventKit.prefilledDraft = nil
            }
        }
        .onChange(of: editingTask) { _ in
            loadEditingTaskIfNeeded()
        }
        .onChange(of: countdownTimeString) { newValue in
            syncCountdownFromInput(newValue)
        }
        .onChange(of: dailyTimeString) { newValue in
            syncDailyTimeFromInput(newValue)
        }
        .onChange(of: intervalTimeString) { newValue in
            syncIntervalFromInput(newValue)
        }
    }
    
    // MARK: - 提醒方式下拉选择器（像素级对齐，箭头展开/收起联动，绝对零挤压，选项必响应）
    private var actionKindPicker: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.14)) {
                isActionPickerExpanded.toggle()
            }
        }) {
            HStack(spacing: 4) {
                Text(actionKind.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary.opacity(0.9))
                    .lineLimit(1)
                    .fixedSize()
                
                Spacer(minLength: 2)
                
                Image(systemName: isActionPickerExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.75))
            }
            .padding(.horizontal, 7)
            .frame(width: 80, height: 24)
            .background(Color.primary.opacity(isActionPickerExpanded ? 0.1 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            if isActionPickerExpanded {
                ZStack(alignment: .topLeading) {
                    // 全局透明背景：捕获外部点击平滑收起
                    Color.black.opacity(0.0001)
                        .frame(width: 1200, height: 1200)
                        .offset(x: -600, y: -600)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                isActionPickerExpanded = false
                            }
                        }
                    
                    // 下拉卡片：处于透明背景上层，紧密咬合按钮底边展开，完全消除悬空缝隙，文字像素级对齐
                    actionKindDropdownList
                        .offset(y: 24)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                }
            }
        }
        .zIndex(500)
    }
    
    // MARK: - 提醒方式展开列表（与按钮 80pt 严丝合缝，文字基准线垂直严格对齐，零挤压）
    private var actionKindDropdownList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(TaskActionKind.allCases) { kind in
                let isSelected = actionKind == kind
                Button(action: {
                    actionKind = kind
                    if audioService.isPlaying && kind != .playAudio {
                        stopAudioPreview()
                    }
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isActionPickerExpanded = false
                    }
                }) {
                    HStack(spacing: 4) {
                        // 1. 文字标签：左侧内边距 4 + 卡片内边距 3 = 7pt，与上方按钮文字起始线完全同一基准对齐
                        Text(kind.title)
                            .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                            .foregroundColor(isSelected ? .primary : .primary.opacity(0.85))
                            .lineLimit(1)
                            .fixedSize()
                        
                        Spacer(minLength: 2)
                        
                        // 2. 选中的项在右侧显示对勾，绝不破坏左侧文字垂直对齐基准线
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        isSelected ? Color.primary.opacity(0.08) : (hoveredActionKind == kind ? Color.primary.opacity(0.04) : Color.clear)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    hoveredActionKind = isHovered ? kind : nil
                    if isHovered { NSCursor.arrow.set() }
                }
            }
        }
        .padding(3)
        .frame(width: 80)
        .contentShape(Rectangle())
        .onHover { isHovered in
            if isHovered { NSCursor.arrow.set() }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.8)
        )
    }
    
    // MARK: - 模式对应时长调整控件（左侧快捷预设，右侧统一微调器，交互严格一致，支持点击数字直接编辑）
    @ViewBuilder
    private var durationAdjustmentView: some View {
        switch selectedMode {
        case .countdown:
            HStack(alignment: .center, spacing: 0) {
                // 左侧快捷选项
                HStack(spacing: 5) {
                    ForEach([(0, 30, "30s"), (25, 0, "25m"), (60, 0, "60m")], id: \.2) { m, s, label in
                        let isSel = isCountdownPresetMatching(minutes: m, seconds: s)
                        Button(action: {
                            countdownMinutes = m
                            countdownSeconds = s
                            countdownTimeString = String(format: "%02d:%02d", m, s)
                        }) {
                            Text(label)
                                .font(.system(size: 11, weight: isSel ? .bold : .medium))
                                .lineLimit(1)
                                .fixedSize()
                                .foregroundColor(isSel ? .accentColor : .secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3.5)
                                .background(isSel ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Spacer()
                
                // 右侧统一时间调节器（三个模式 100% 像素级复用同一个组件）
                unifiedTimeStepper(
                    text: $countdownTimeString,
                    onMinus: { stepCountdown(isMinus: true) },
                    onPlus: { stepCountdown(isMinus: false) },
                    onSubmit: { commitCountdown() }
                )
            }
            
        case .daily:
            HStack(alignment: .center, spacing: 0) {
                // 左侧快捷选项
                HStack(spacing: 5) {
                    ForEach(["09:00", "14:00", "18:00"], id: \.self) { timeStr in
                        let parts = timeStr.split(separator: ":")
                        let isSel = isDailyTimeMatching(hourStr: String(parts[0]), minStr: String(parts[1]))
                        Button(action: {
                            setDailyTime(hourStr: String(parts[0]), minStr: String(parts[1]))
                            dailyTimeString = timeStr
                        }) {
                            Text(timeStr)
                                .font(.system(size: 10.5, weight: isSel ? .bold : .medium))
                                .lineLimit(1)
                                .fixedSize()
                                .foregroundColor(isSel ? .indigo : .secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3.5)
                                .background(isSel ? Color.indigo.opacity(0.14) : Color.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Spacer()
                
                // 右侧统一时间调节器 (加减15分钟或就地输入，与倒计时完全一致)
                unifiedTimeStepper(
                    text: $dailyTimeString,
                    onMinus: { stepDailyTime(minutesOffset: -15) },
                    onPlus: { stepDailyTime(minutesOffset: 15) },
                    onSubmit: { commitDailyTime() }
                )
            }
            
        case .interval:
            HStack(alignment: .center, spacing: 0) {
                // 左侧快捷选项
                HStack(spacing: 5) {
                    ForEach([(0, 30, "30s"), (25, 0, "25m"), (60, 0, "60m")], id: \.2) { m, s, label in
                        let isSel = isIntervalPresetMatching(minutes: m, seconds: s)
                        Button(action: {
                            intervalMinutes = m
                            intervalSeconds = s
                            intervalTimeString = String(format: "%02d:%02d", m, s)
                        }) {
                            Text(label)
                                .font(.system(size: 11, weight: isSel ? .bold : .medium))
                                .lineLimit(1)
                                .fixedSize()
                                .foregroundColor(isSel ? .teal : .secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3.5)
                                .background(isSel ? Color.teal.opacity(0.14) : Color.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Spacer()
                
                // 右侧统一时间调节器（三个模式 100% 像素级复用同一个组件）
                unifiedTimeStepper(
                    text: $intervalTimeString,
                    onMinus: { stepInterval(isMinus: true) },
                    onPlus: { stepInterval(isMinus: false) },
                    onSubmit: { commitInterval() }
                )
            }
        }
    }
    
    // MARK: - 统一时间微调组件（三个模式 100% 像素级复用同一个组件）
    private func unifiedTimeStepper(
        text: Binding<String>,
        onMinus: @escaping () -> Void,
        onPlus: @escaping () -> Void,
        onSubmit: @escaping () -> Void
    ) -> some View {
        UnifiedTimeStepperView(
            text: text,
            onMinus: onMinus,
            onPlus: onPlus,
            onSubmit: onSubmit
        )
    }
    
    // MARK: - 快捷预设与输入框匹配判定
    private func isCountdownPresetMatching(minutes m: Int, seconds s: Int) -> Bool {
        guard countdownMinutes == m && countdownSeconds == s else { return false }
        let clean = countdownTimeString.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.contains(":") {
            let parts = clean.split(separator: ":")
            if parts.count == 2, let parsedM = Int(parts[0]), let parsedS = Int(parts[1]) {
                return parsedM == m && parsedS == s
            }
            return false
        } else if let num = Int(clean) {
            return num == m && s == 0
        }
        return false
    }

    private func isIntervalPresetMatching(minutes m: Int, seconds s: Int) -> Bool {
        guard intervalMinutes == m && intervalSeconds == s else { return false }
        let clean = intervalTimeString.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.contains(":") {
            let parts = clean.split(separator: ":")
            if parts.count == 2, let parsedM = Int(parts[0]), let parsedS = Int(parts[1]) {
                return parsedM == m && parsedS == s
            }
            return false
        } else if let num = Int(clean) {
            return num == m && s == 0
        }
        return false
    }

    private func isDailyTimeMatching(hourStr: String, minStr: String) -> Bool {
        guard let h = Int(hourStr), let m = Int(minStr) else { return false }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: dailyTime)
        guard comps.hour == h && comps.minute == m else { return false }
        let clean = dailyTimeString.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.contains(":") {
            let parts = clean.split(separator: ":")
            if parts.count == 2, let parsedH = Int(parts[0]), let parsedM = Int(parts[1]) {
                return parsedH == h && parsedM == m
            }
        }
        return false
    }

    // MARK: - 实时打字同步（实时更新数值与快捷预设高亮，不破坏用户打字中的字符串）
    private func syncCountdownFromInput(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.contains(":") {
            let parts = clean.split(separator: ":")
            if parts.count == 2, let m = Int(parts[0]), let s = Int(parts[1]), s >= 0 && s < 60 && m >= 0 {
                countdownMinutes = min(720, m)
                countdownSeconds = s
            }
        } else if let num = Int(clean), num >= 0 {
            countdownMinutes = min(720, num)
            countdownSeconds = 0
        }
    }

    private func syncDailyTimeFromInput(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.contains(":") {
            let parts = clean.split(separator: ":")
            if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), h >= 0 && h < 24 && m >= 0 && m < 60 {
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                comps.hour = h
                comps.minute = m
                dailyTime = Calendar.current.date(from: comps) ?? dailyTime
            }
        }
    }

    private func syncIntervalFromInput(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.contains(":") {
            let parts = clean.split(separator: ":")
            if parts.count == 2, let m = Int(parts[0]), let s = Int(parts[1]), s >= 0 && s < 60 && m >= 0 {
                intervalMinutes = min(720, m)
                intervalSeconds = s
            }
        } else if let num = Int(clean), num >= 0 {
            intervalMinutes = min(720, num)
            intervalSeconds = 0
        }
    }

    // MARK: - 倒计时步进与提交
    private func stepCountdown(isMinus: Bool) {
        commitCountdown()
        let currentTotal = countdownMinutes * 60 + countdownSeconds
        let newTotal: Int
        if isMinus {
            if currentTotal <= 60 {
                newTotal = max(5, currentTotal - 5)
            } else if currentTotal % 60 != 0 {
                newTotal = max(60, (currentTotal / 60) * 60)
            } else {
                newTotal = max(60, currentTotal - 60)
            }
        } else {
            if currentTotal < 60 {
                newTotal = currentTotal + 5
            } else {
                newTotal = currentTotal + 60
            }
        }
        countdownMinutes = min(720, newTotal / 60)
        countdownSeconds = newTotal % 60
        countdownTimeString = String(format: "%02d:%02d", countdownMinutes, countdownSeconds)
    }
    
    private func commitCountdown() {
        let clean = countdownTimeString.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.contains(":") {
            let parts = clean.split(separator: ":")
            if parts.count == 2, let m = Int(parts[0]), let s = Int(parts[1]) {
                countdownMinutes = max(0, min(720, m))
                countdownSeconds = max(0, min(59, s))
                countdownTimeString = String(format: "%02d:%02d", countdownMinutes, countdownSeconds)
                return
            }
        } else if let num = Int(clean) {
            countdownMinutes = max(0, min(720, num))
            countdownSeconds = 0
            countdownTimeString = String(format: "%02d:%02d", countdownMinutes, countdownSeconds)
            return
        }
        countdownTimeString = String(format: "%02d:%02d", countdownMinutes, countdownSeconds)
    }
    
    // MARK: - 每日定时步进与提交
    private func stepDailyTime(minutesOffset: Int) {
        commitDailyTime()
        if let newDate = Calendar.current.date(byAdding: .minute, value: minutesOffset, to: dailyTime) {
            dailyTime = newDate
            dailyTimeString = formattedDailyTime
        }
    }
    
    private func commitDailyTime() {
        let clean = dailyTimeString.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.contains(":") {
            let parts = clean.split(separator: ":")
            if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), h >= 0 && h < 24 && m >= 0 && m < 60 {
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                comps.hour = h
                comps.minute = m
                dailyTime = Calendar.current.date(from: comps) ?? dailyTime
                dailyTimeString = String(format: "%02d:%02d", h, m)
                return
            }
        }
        dailyTimeString = formattedDailyTime
    }
    
    // MARK: - 循环间隔步进与提交
    private func stepInterval(isMinus: Bool) {
        commitInterval()
        let currentTotal = intervalMinutes * 60 + intervalSeconds
        let newTotal: Int
        if isMinus {
            if currentTotal <= 60 {
                newTotal = max(5, currentTotal - 5)
            } else if currentTotal % 60 != 0 {
                newTotal = max(60, (currentTotal / 60) * 60)
            } else {
                newTotal = max(60, currentTotal - 60)
            }
        } else {
            if currentTotal < 60 {
                newTotal = currentTotal + 5
            } else {
                newTotal = currentTotal + 60
            }
        }
        intervalMinutes = min(720, newTotal / 60)
        intervalSeconds = newTotal % 60
        intervalTimeString = String(format: "%02d:%02d", intervalMinutes, intervalSeconds)
    }
    
    private func commitInterval() {
        let clean = intervalTimeString.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.contains(":") {
            let parts = clean.split(separator: ":")
            if parts.count == 2, let m = Int(parts[0]), let s = Int(parts[1]) {
                intervalMinutes = max(0, min(720, m))
                intervalSeconds = max(0, min(59, s))
                intervalTimeString = String(format: "%02d:%02d", intervalMinutes, intervalSeconds)
                return
            }
        } else if let num = Int(clean) {
            intervalMinutes = max(0, min(720, num))
            intervalSeconds = 0
            intervalTimeString = String(format: "%02d:%02d", intervalMinutes, intervalSeconds)
            return
        }
        intervalTimeString = String(format: "%02d:%02d", intervalMinutes, intervalSeconds)
    }
    
    private var twoDigitFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.formatWidth = 2
        f.paddingCharacter = "0"
        f.minimum = 0
        f.maximum = 999
        return f
    }
    
    private var formattedDailyTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: dailyTime)
    }
    
    private func setDailyTime(hourStr: String, minStr: String) {
        guard let h = Int(hourStr), let m = Int(minStr) else { return }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = h
        comps.minute = m
        dailyTime = Calendar.current.date(from: comps) ?? dailyTime
    }
    
    private func adjustDailyTime(minutesOffset: Int) {
        if let newDate = Calendar.current.date(byAdding: .minute, value: minutesOffset, to: dailyTime) {
            dailyTime = newDate
        }
    }
    
    // MARK: - 动态内联设置区
    @ViewBuilder
    private var inlineActionConfigView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().opacity(0.25)
            
            switch actionKind {
            case .textNotification, .soundOnly:
                EmptyView()
                
            case .playAudio:
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: 11))
                            .foregroundColor(isAudioFileMissing ? .red : .green)
                        
                        // 音频快速选择
                        Picker("", selection: $selectedAudioName) {
                            Text("眼保健操").tag("眼保健操")
                            Text("八段锦口令").tag("八段锦口令")
                            Text("自定义...").tag("自定义")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 130)
                        .onChange(of: selectedAudioName) { name in
                            if name == "眼保健操" {
                                selectedAudioPath = "Resources/Audio/眼保健操.mp3"
                            } else if name == "八段锦口令" {
                                selectedAudioPath = "Resources/Audio/健身气功八段锦口令.mp3"
                            } else if name == "自定义" {
                                selectCustomAudioFile()
                            }
                        }
                        
                        // 试听 / 停止 双态按钮（点击进入播放状态，再次点击停止播放）
                        Button(action: toggleAudioPreview) {
                            HStack(spacing: 3) {
                                Image(systemName: isCurrentAudioPlaying ? "stop.fill" : "play.fill")
                                    .font(.system(size: 8))
                                Text(isCurrentAudioPlaying ? "停止" : "试听")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(isCurrentAudioPlaying ? .white : (isAudioFileMissing ? .red : .primary))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(isCurrentAudioPlaying ? Color.green : (isAudioFileMissing ? Color.red.opacity(0.12) : Color.primary.opacity(0.08)))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .floatingTooltip(isCurrentAudioPlaying ? "停止播放" : (isAudioFileMissing ? "音频文件已丢失" : "试听音频"))
                        
                        Spacer()
                        
                        // 音量滑块
                        HStack(spacing: 4) {
                            Image(systemName: "speaker.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Slider(value: $audioVolume, in: 0.1...1.0)
                                .frame(width: 60)
                                .scaleEffect(0.8)
                        }
                    }
                    
                    // 自定义音频文件丢失明确告警
                    if isAudioFileMissing {
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                            Text("⚠️ 音频文件已丢失")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.red)
                            
                            Spacer()
                            
                            Button("重新选择") {
                                selectCustomAudioFile()
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
                .padding(.vertical, 2)
                
            case .openURL:
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 11))
                        .foregroundColor(.blue)
                    
                    TextField("https:// 网址", text: $targetURLString)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.top, 2)
    }
    
    // MARK: - 联想建议列表
    private var suggestionResultsView: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(searchResults) { item in
                Button(action: {
                    taskTitle = item.title
                    if let link = item.url?.absoluteString {
                        actionKind = .openURL
                        targetURLString = link
                    }
                    
                    if let (h, m) = item.suggestedHourMinute {
                        selectedMode = .daily
                        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                        comps.hour = h
                        comps.minute = m
                        dailyTime = Calendar.current.date(from: comps) ?? dailyTime
                        dailyTimeString = String(format: "%02d:%02d", h, m)
                        let timeStr = String(format: "%02d:%02d", h, m)
                        parsedTimeResult = ParsedTimeResult(
                            mode: .daily(hour: h, minute: m),
                            cleanedTitle: item.title,
                            matchedText: timeStr,
                            summaryText: timeStr
                        )
                    }
                    
                    isShowingSuggestions = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isTitleFocused = true
                    }
                }) {
                    HStack(spacing: 7) {
                        Image(systemName: item.iconName)
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                            .frame(width: 16)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            Text(item.subtitle)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.8)
        )
    }
    
    // MARK: - 辅助计算与事件处理（动态文案：[时间]提醒我）
    private func formatDurationString(minutes: Int, seconds: Int) -> String {
        if minutes == 0 {
            return "\(max(1, seconds))秒"
        } else if seconds == 0 {
            return "\(minutes)分钟"
        } else {
            return "\(minutes)分\(seconds)秒"
        }
    }
    
    private var defaultPlaceholder: String {
        if editingTask != nil {
            return "任务名称"
        }
        switch selectedMode {
        case .countdown:
            return formatDurationString(minutes: countdownMinutes, seconds: countdownSeconds)
        case .daily:
            return formattedDailyTime
        case .interval:
            return "每\(formatDurationString(minutes: intervalMinutes, seconds: intervalSeconds))"
        }
    }
    
    private func selectCustomAudioFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        if panel.runModal() == .OK, let url = panel.url {
            selectedAudioPath = url.path
            selectedAudioName = url.lastPathComponent
        }
    }
    
    private func toggleAudioPreview() {
        if audioService.isPlaying {
            audioService.stop(fadeOut: false)
        } else {
            if isAudioFileMissing {
                showInlineToast("音频文件已丢失，请重新选择本地音频")
                return
            }
            audioService.playLocalFile(
                atPath: selectedAudioPath,
                displayName: selectedAudioName,
                volume: audioVolume,
                fadeIn: false
            )
        }
    }
    
    private func stopAudioPreview() {
        if audioService.isPlaying {
            audioService.stop(fadeOut: false)
        }
    }
    
    private func showInlineToast(_ message: String) {
        withAnimation {
            inlineToast = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                if self.inlineToast == message {
                    self.inlineToast = nil
                }
            }
        }
    }
    
    private func loadEditingTaskIfNeeded() {
        guard let task = editingTask else { return }
        taskTitle = task.name
        parsedTimeResult = nil
        
        switch task.trigger {
        case .countdown(let totalSeconds):
            selectedMode = .countdown
            countdownMinutes = totalSeconds / 60
            countdownSeconds = totalSeconds % 60
            countdownTimeString = String(format: "%02d:%02d", countdownMinutes, countdownSeconds)
        case .daily(let hour, let minute):
            selectedMode = .daily
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            comps.hour = hour
            comps.minute = minute
            dailyTime = Calendar.current.date(from: comps) ?? Date()
            dailyTimeString = String(format: "%02d:%02d", hour, minute)
        case .interval(let intervalSeconds):
            selectedMode = .interval
            intervalMinutes = intervalSeconds / 60
            self.intervalSeconds = intervalSeconds % 60
            intervalTimeString = String(format: "%02d:%02d", intervalMinutes, self.intervalSeconds)
        case .once:
            selectedMode = .countdown
            countdownMinutes = 25
            countdownSeconds = 0
            countdownTimeString = "25:00"
        }
        
        switch task.action {
        case .none:
            actionKind = .soundOnly
        case .popupContent:
            actionKind = .textNotification
        case .playLocalAudio(let path, let name, _, let vol, _):
            actionKind = .playAudio
            selectedAudioPath = path
            selectedAudioName = name.isEmpty ? (path as NSString).lastPathComponent : name
            audioVolume = vol
        case .openURL(let urlString):
            actionKind = .openURL
            targetURLString = urlString
        }
    }
    
    private func cancelEdit() {
        editingTask = nil
        taskTitle = ""
        parsedTimeResult = nil
        actionKind = .textNotification
        stopAudioPreview()
    }
    
    private func submitTask() {
        stopAudioPreview()
        
        let trimmed = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. 优先权威解析：若输入文本包含自然语言时间，立即更新时间与模式
        let activeParsed = NaturalLanguageTimeParser.shared.parse(trimmed) ?? parsedTimeResult
        
        if let parsed = activeParsed {
            switch parsed.mode {
            case .countdown(let m, let s):
                selectedMode = .countdown
                countdownMinutes = m
                countdownSeconds = s
                countdownTimeString = String(format: "%02d:%02d", m, s)
            case .daily(let h, let m):
                selectedMode = .daily
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                comps.hour = h
                comps.minute = m
                dailyTime = Calendar.current.date(from: comps) ?? dailyTime
                dailyTimeString = String(format: "%02d:%02d", h, m)
            case .interval(let m, let s):
                selectedMode = .interval
                intervalMinutes = m
                intervalSeconds = s
                intervalTimeString = String(format: "%02d:%02d", m, s)
            }
        } else {
            // 保底：确保输入框当前的时间已被解析提交
            switch selectedMode {
            case .countdown:
                commitCountdown()
            case .daily:
                commitDailyTime()
            case .interval:
                commitInterval()
            }
        }
        
        // 构建 Trigger (精确到秒)
        let trigger: TriggerType
        switch selectedMode {
        case .countdown:
            let total = countdownMinutes * 60 + countdownSeconds
            trigger = .countdown(totalSeconds: max(1, total))
        case .daily:
            let comps = Calendar.current.dateComponents([.hour, .minute], from: dailyTime)
            trigger = .daily(hour: comps.hour ?? 9, minute: comps.minute ?? 30)
        case .interval:
            let total = intervalMinutes * 60 + intervalSeconds
            trigger = .interval(intervalSeconds: max(1, total))
        }
        
        // 构建默认名称（去专注、去打卡，普通实用，支持秒）
        let finalName: String
        if let parsed = activeParsed, !parsed.cleanedTitle.isEmpty {
            finalName = parsed.cleanedTitle
        } else if !trimmed.isEmpty && activeParsed == nil {
            finalName = trimmed
        } else {
            switch selectedMode {
            case .countdown:
                finalName = formatDurationString(minutes: countdownMinutes, seconds: countdownSeconds)
            case .daily:
                finalName = dailyTimeString
            case .interval:
                finalName = "每\(formatDurationString(minutes: intervalMinutes, seconds: intervalSeconds))"
            }
        }
        
        // 构建 Action（四种正交方式）
        let action: ActionType
        switch actionKind {
        case .textNotification:
            action = .popupContent(mode: .textNotification(message: finalName))
        case .soundOnly:
            action = .none
        case .playAudio:
            action = .playLocalAudio(
                filePath: selectedAudioPath,
                displayName: selectedAudioName,
                loop: false,
                volume: audioVolume,
                durationSeconds: nil
            )
        case .openURL:
            action = .openURL(urlString: targetURLString)
        }
        
        if let existing = editingTask {
            var updated = existing
            updated.name = finalName
            updated.trigger = trigger
            updated.action = action
            if case .countdown(let totalSeconds) = trigger {
                updated.countdownRemainingSeconds = totalSeconds
            }
            scheduler.updateTask(updated)
            editingTask = nil
        } else {
            let newTask = ScheduleTask(
                id: UUID(),
                name: finalName,
                trigger: trigger,
                action: action,
                isEnabled: true,
                isPaused: false,
                createdAt: Date(),
                lastTriggeredAt: nil
            )
            scheduler.addTask(newTask)
        }
        
        taskTitle = ""
        parsedTimeResult = nil
        isShowingSuggestions = false
    }
    
    // MARK: - 任务标题输入与长文本处理
    private func handleTaskTitleChange(_ newValue: String) {
        // 1. 若用户在输入框按回车键（末尾或内部检测到换行符），先解析自然语言时间，再触发提交
        if newValue.hasSuffix("\n") || newValue.hasSuffix("\r") || newValue.contains("\n") {
            let cleaned = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                taskTitle = cleaned
                handleNaturalLanguageInput(cleaned)
                submitTask()
                return
            }
        }
        
        // 2. 长文本规整：将硬换行符转换为统一空格，让输入框自然折行展开，彻底杜绝上方切边被吞
        let sanitized = newValue
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        
        if sanitized != newValue {
            taskTitle = sanitized
            return
        }
        
        // 3. 智能检测链接：若粘贴的长文本中包含 URL（如小红书、网页链接），自动提取到链接动作中
        if let detectedURL = extractFirstURL(from: sanitized) {
            targetURLString = detectedURL
            if actionKind == .textNotification {
                actionKind = .openURL
            }
        }
        
        isShowingSuggestions = !sanitized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        handleNaturalLanguageInput(sanitized)
    }
    
    /// 从长文本中提取首个 http/https 链接
    private func extractFirstURL(from text: String) -> String? {
        let pattern = #"https?://[^\s<>\"'，。；！？]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) else {
            return nil
        }
        return (text as NSString).substring(with: match.range)
    }

    // MARK: - 自然语言输入实时处理与提示
    private func handleNaturalLanguageInput(_ text: String) {
        if let result = NaturalLanguageTimeParser.shared.parse(text) {
            parsedTimeResult = result
            switch result.mode {
            case .countdown(let m, let s):
                selectedMode = .countdown
                countdownMinutes = m
                countdownSeconds = s
                countdownTimeString = String(format: "%02d:%02d", m, s)
            case .daily(let h, let m):
                selectedMode = .daily
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                comps.hour = h
                comps.minute = m
                dailyTime = Calendar.current.date(from: comps) ?? dailyTime
                dailyTimeString = String(format: "%02d:%02d", h, m)
            case .interval(let m, let s):
                selectedMode = .interval
                intervalMinutes = m
                intervalSeconds = s
                intervalTimeString = String(format: "%02d:%02d", m, s)
            }
        } else {
            parsedTimeResult = nil
        }
    }
    
    @ViewBuilder
    private func naturalLanguageHintBar(parsed: ParsedTimeResult) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.accentColor)
            Text(parsed.summaryText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.accentColor)
            if !parsed.cleanedTitle.isEmpty {
                Text("· \(parsed.cleanedTitle)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 0.8)
        )
    }
    
    private func applyPrefilledDraft(_ draft: PrefilledTaskDraft) {
        taskTitle = draft.title
        if let link = draft.targetURLString, !link.isEmpty {
            actionKind = .openURL
            targetURLString = link
        }
        
        // 自动同步时间与对应模式
        if let h = draft.targetHour, let m = draft.targetMinute {
            selectedMode = .daily
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            comps.hour = h
            comps.minute = m
            dailyTime = Calendar.current.date(from: comps) ?? dailyTime
            dailyTimeString = String(format: "%02d:%02d", h, m)
            let timeStr = String(format: "%02d:%02d", h, m)
            parsedTimeResult = ParsedTimeResult(
                mode: .daily(hour: h, minute: m),
                cleanedTitle: draft.title,
                matchedText: timeStr,
                summaryText: timeStr
            )
        } else if let minutes = draft.suggestedCountdownMinutes {
            selectedMode = .countdown
            countdownMinutes = minutes
            countdownSeconds = 0
            countdownTimeString = String(format: "%02d:00", minutes)
            parsedTimeResult = ParsedTimeResult(
                mode: .countdown(minutes: minutes, seconds: 0),
                cleanedTitle: draft.title,
                matchedText: "\(minutes)分钟",
                summaryText: "\(minutes)分钟"
            )
        }
        
        isShowingSuggestions = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isTitleFocused = true
        }
    }
}

// MARK: - 连续按住步进状态管理
private final class ContinuousPressState: ObservableObject {
    @Published var isPressing = false
    private var timer: Timer?
    var onAction: (() -> Void)?
    
    func start() {
        guard !isPressing else { return }
        isPressing = true
        onAction?()
        
        timer?.invalidate()
        let initialTimer = Timer(timeInterval: 0.35, repeats: false) { [weak self] _ in
            guard let self = self, self.isPressing else { return }
            self.onAction?()
            self.timer?.invalidate()
            let repeatTimer = Timer(timeInterval: 0.09, repeats: true) { [weak self] _ in
                guard let self = self, self.isPressing else {
                    self?.stop()
                    return
                }
                self.onAction?()
            }
            RunLoop.main.add(repeatTimer, forMode: .common)
            self.timer = repeatTimer
        }
        RunLoop.main.add(initialTimer, forMode: .common)
        self.timer = initialTimer
    }
    
    func stop() {
        isPressing = false
        timer?.invalidate()
        timer = nil
    }
    
    deinit {
        timer?.invalidate()
    }
}

// MARK: - 支持长按连续触发的无背景按钮
private struct ContinuousPressButton: View {
    let systemName: String
    let helpText: String
    let action: () -> Void
    
    @StateObject private var pressState = ContinuousPressState()
    private let size: CGFloat = 20
    
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.primary.opacity(pressState.isPressing ? 0.95 : 0.65))
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .floatingTooltip(helpText)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        pressState.onAction = action
                        let inside = CGRect(origin: .zero, size: CGSize(width: size, height: size))
                            .contains(value.location)
                        if inside {
                            pressState.start()
                        } else {
                            pressState.stop()
                        }
                    }
                    .onEnded { _ in
                        pressState.stop()
                    }
            )
            .onDisappear {
                pressState.stop()
            }
    }
}

// MARK: - 统一时间微调与输入组件
private struct UnifiedTimeStepperView: View {
    @Binding var text: String
    let onMinus: () -> Void
    let onPlus: () -> Void
    let onSubmit: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 5) {
            ContinuousPressButton(
                systemName: "chevron.left",
                helpText: "减少时间"
            ) {
                onSubmit()
                onMinus()
            }
            
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular, design: .default))
                .multilineTextAlignment(.center)
                .frame(width: 48, height: 21)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
                .focused($isFocused)
                .onSubmit {
                    onSubmit()
                }
                .onChange(of: isFocused) { focused in
                    if !focused {
                        onSubmit()
                    }
                }
            
            ContinuousPressButton(
                systemName: "chevron.right",
                helpText: "增加时间"
            ) {
                onSubmit()
                onPlus()
            }
        }
    }
}
