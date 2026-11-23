import SwiftUI
import AppKit

// MARK: - 触发模式枚举
enum TriggerMode: Int, CaseIterable, Identifiable {
    case countdown = 0
    case daily = 1
    case interval = 2
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .countdown: return "倒计时"
        case .daily: return "每天定时"
        case .interval: return "循环间隔"
        }
    }
    
    var icon: String {
        switch self {
        case .countdown: return "timer"
        case .daily: return "clock.arrow.circlepath"
        case .interval: return "repeat"
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
    
    // 基本状态
    @State private var taskTitle: String = ""
    @State private var selectedMode: TriggerMode = .countdown
    
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
    
    // 联想搜索
    @State private var isShowingSuggestions: Bool = false
    
    private var searchResults: [EventKitSearchResult] {
        guard isShowingSuggestions else { return [] }
        return eventKit.search(query: taskTitle)
    }
    
    public init(editingTask: Binding<ScheduleTask?> = .constant(nil)) {
        self._editingTask = editingTask
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 1. 主输入行：名称输入 + 提醒方式下拉框 + 开始/保存按钮 + 取消按钮
            HStack(spacing: 8) {
                // 任务名称输入框（无多余图标，文案精简）
                HStack(spacing: 6) {
                    TextField(defaultPlaceholder, text: $taskTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .onChange(of: taskTitle) { val in
                            isShowingSuggestions = !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        }
                        .onSubmit {
                            submitTask()
                        }
                    
                    if !taskTitle.isEmpty {
                        Button(action: {
                            taskTitle = ""
                            isShowingSuggestions = false
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.8)
                )
                
                // 提醒方式下拉框
                Menu {
                    ForEach(TaskActionKind.allCases) { kind in
                        Button(action: {
                            actionKind = kind
                            if audioService.isPlaying && kind != .playAudio {
                                stopAudioPreview()
                            }
                        }) {
                            HStack {
                                Image(systemName: kind.icon)
                                Text(kind.title)
                                if actionKind == kind {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: actionKind.icon)
                            .font(.system(size: 10))
                        Text(actionKind.title)
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6.5)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("选择到期提醒动作")
                
                // 开始 / 保存按钮 (纯图标极简呈现，不占横向空间)
                Button(action: submitTask) {
                    Image(systemName: editingTask != nil ? "checkmark" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(editingTask != nil ? "保存修改" : "立即创建并启动")
                
                // 若处于就地编辑模式，展示取消按钮 (纯图标极简呈现)
                if editingTask != nil {
                    Button(action: cancelEdit) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("取消修改")
                }
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
        .onAppear {
            eventKit.checkPermissions()
            countdownTimeString = String(format: "%02d:%02d", countdownMinutes, countdownSeconds)
            dailyTimeString = formattedDailyTime
            intervalTimeString = String(format: "%02d:%02d", intervalMinutes, intervalSeconds)
            loadEditingTaskIfNeeded()
        }
        .onChange(of: editingTask) { _ in
            loadEditingTaskIfNeeded()
        }
    }
    
    // MARK: - 模式对应时长调整控件（左侧快捷预设，右侧统一微调器，交互严格一致，支持点击数字直接编辑）
    @ViewBuilder
    private var durationAdjustmentView: some View {
        switch selectedMode {
        case .countdown:
            HStack(alignment: .center, spacing: 0) {
                // 左侧快捷选项
                HStack(spacing: 5) {
                    ForEach([(0, 30, "30s"), (1, 0, "1m"), (5, 0, "5m"), (25, 0, "25m")], id: \.2) { m, s, label in
                        let isSel = countdownMinutes == m && countdownSeconds == s
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
                HStack(spacing: 4) {
                    ForEach(["09:00", "09:30", "14:00", "18:00"], id: \.self) { timeStr in
                        let parts = timeStr.split(separator: ":")
                        let isSel = isDailyTimeMatching(hourStr: String(parts[0]), minStr: String(parts[1]))
                        Button(action: {
                            setDailyTime(hourStr: String(parts[0]), minStr: String(parts[1]))
                            dailyTimeString = timeStr
                        }) {
                            Text(timeStr)
                                .font(.system(size: 10, weight: isSel ? .bold : .medium))
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
                // 左侧快捷选项（支持秒）
                HStack(spacing: 5) {
                    ForEach([(0, 30, "30s"), (1, 0, "1m"), (15, 0, "15m"), (30, 0, "30m")], id: \.2) { m, s, label in
                        let isSel = intervalMinutes == m && intervalSeconds == s
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
        HStack(spacing: 5) {
            Button(action: onMinus) {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary.opacity(0.75))
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("减少时间")
            
            TextField("", text: text)
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
                .onSubmit { onSubmit() }
            
            Button(action: onPlus) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary.opacity(0.75))
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("增加时间")
        }
    }
    
    // MARK: - 倒计时步进与提交
    private func stepCountdown(isMinus: Bool) {
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
    
    private func isDailyTimeMatching(hourStr: String, minStr: String) -> Bool {
        guard let h = Int(hourStr), let m = Int(minStr) else { return false }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: dailyTime)
        return comps.hour == h && comps.minute == m
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
                            Text("自定义本地文件...").tag("自定义")
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
                        .help(isCurrentAudioPlaying ? "停止播放" : (isAudioFileMissing ? "音频文件已丢失" : "试听音频"))
                        
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
                            Text("⚠️ 自定义音频文件丢失或已被移除")
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
                    
                    TextField("输入到期自动打开的网页链接", text: $targetURLString)
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
            HStack {
                Text("系统日历与提醒联想")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { isShowingSuggestions = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
            .padding(.top, 3)
            
            ForEach(searchResults) { item in
                Button(action: {
                    taskTitle = item.title
                    isShowingSuggestions = false
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
                        
                        Text("填入")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
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
            return "\(formatDurationString(minutes: countdownMinutes, seconds: countdownSeconds))后提醒我"
        case .daily:
            return "\(formattedDailyTime)提醒我"
        case .interval:
            return "每\(formatDurationString(minutes: intervalMinutes, seconds: intervalSeconds))提醒我"
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
        actionKind = .textNotification
        stopAudioPreview()
    }
    
    private func submitTask() {
        stopAudioPreview()
        let trimmed = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        
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
        if !trimmed.isEmpty {
            finalName = trimmed
        } else {
            switch selectedMode {
            case .countdown:
                finalName = "倒计时 \(formatDurationString(minutes: countdownMinutes, seconds: countdownSeconds))"
            case .daily:
                finalName = "每日提醒"
            case .interval:
                finalName = "循环 \(formatDurationString(minutes: intervalMinutes, seconds: intervalSeconds))"
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
        isShowingSuggestions = false
    }
}
