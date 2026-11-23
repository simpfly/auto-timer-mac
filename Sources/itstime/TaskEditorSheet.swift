import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TaskEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var scheduler = SchedulerEngine.shared
    @ObservedObject var audioService = AudioService.shared
    
    var editingTask: ScheduleTask?
    var onSave: ((ScheduleTask) -> Void)?
    
    // 表单状态
    @State private var name: String = ""
    @State private var triggerMode: Int = 0 // 0: 倒计时, 1: 每日定时, 2: 循环间隔
    
    @State private var onceDate = Date()

    // 倒计时参数 (总秒数)
    @State private var countdownMinutes: Int = 25
    @State private var countdownSeconds: Int = 0
    
    // 每日定时参数
    @State private var dailyHour: Int = 9
    @State private var dailyMinute: Int = 30
    @State private var dailyPickerDate: Date = {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 9
        comps.minute = 30
        return Calendar.current.date(from: comps) ?? Date()
    }()
    
    // 循环间隔参数 (分与秒)
    @State private var intervalMinutes: Int = 1
    @State private var intervalSeconds: Int = 0
    
    // 动作类型 0: 仅提醒, 1: 清单/日程, 2: 播放音频, 3: 打开链接
    @State private var actionTypeIndex: Int = 0
    
    // Checklist/日程参数
    @State private var popupModeIndex: Int = 0 // 0: 自定义清单, 1: 今日日程
    @State private var newChecklistText: String = ""
    @State private var checklistItems: [ChecklistItem] = [
        ChecklistItem(text: "检查当天工作目标"),
        ChecklistItem(text: "喝一杯温水"),
        ChecklistItem(text: "站立活动或深呼吸")
    ]
    
    // 本地音频参数
    @State private var audioPath: String = ""
    @State private var audioDisplayName: String = ""
    @State private var audioLoop: Bool = false
    @State private var audioVolume: Double = 0.8
    @State private var hasDurationLimit: Bool = false
    @State private var durationLimitMinutes: Int = 5
    @State private var isDropTargeted: Bool = false
    
    // 链接参数
    @State private var urlString: String = "https://"
    
    // 试听状态：直接响应音频服务实际播放状态
    private var isPreviewing: Bool {
        audioService.isPlaying
    }
    
    var inlineDate: Date?
    var validTime = true
    var onCancelInline: (() -> Void)?

    init(editingTask: ScheduleTask? = nil, inlineDate: Date? = nil, validTime: Bool = true, onCancelInline: (() -> Void)? = nil, onSave: ((ScheduleTask) -> Void)? = nil) {
        self.editingTask = editingTask
        self.inlineDate = inlineDate
        self.validTime = validTime
        self.onCancelInline = onCancelInline
        self.onSave = onSave
    }
    
    var body: some View {
        Group {
            if inlineDate != nil {
                VStack(alignment: .leading, spacing: 9) {
                    TextField("任务名称（选填）", text: $name).textFieldStyle(.roundedBorder)
                    actionSection
                    HStack {
                        Spacer()
                        Button("取消") { onCancelInline?() }.keyboardShortcut(.cancelAction)
                        Button(editingTask == nil ? "新增任务" : "保存修改") { saveAndDismiss() }
                            .keyboardShortcut(.defaultAction)
                            .buttonStyle(.borderedProminent)
                            .disabled(isSaveDisabled)
                    }
                }
                .onAppear { populateData() }
                .onDisappear { stopPreview() }
            } else {
                sheetContent
            }
        }
        .disableFocusEffect()
    }

    private var dynamicHeight: CGFloat {
        switch actionTypeIndex {
        case 1:
            return 520
        case 2:
            return 490
        case 3:
            return 430
        default:
            return 410
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.accentColor)
                Text("到期动作")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            Picker("", selection: $actionTypeIndex) {
                Text("仅提醒").tag(0)
                Text("清单/日程").tag(1)
                Text("播放音频").tag(2)
                Text("打开链接").tag(3)
            }
            .pickerStyle(.segmented)
            
            if actionTypeIndex == 0 {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.accentColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("系统横幅通知")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("时间到达时通过系统通知中心轻柔提醒，不打扰当前专注")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassPanel(cornerRadius: 8)
                .transition(.opacity)
            } else if actionTypeIndex == 1 {
                checklistConfigView
            } else if actionTypeIndex == 2 {
                localAudioConfigView
            } else if actionTypeIndex == 3 {
                urlConfigView
            }
        }
    }

    private var sheetContent: some View {
        ZStack {
            Color.clear
                .background(.regularMaterial)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 1. 结构化顶栏：标题、副标题与关闭入口
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: editingTask == nil ? "plus" : "slider.horizontal.3")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(editingTask == nil ? "新建定时任务" : "编辑任务")
                            .font(.system(size: 15, weight: .bold))
                        Text(editingTask == nil ? "设置时间触发机制与到期动作" : "修改当前任务的时钟机制与动作")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        stopPreview()
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("关闭 (Esc)")
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 12)
                
                Divider()
                    .opacity(0.2)
                
                // 2. 中间自适应内容区
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        // 任务名称精致输入条
                        HStack(spacing: 8) {
                            Image(systemName: "pencil.line")
                                .font(.system(size: 13))
                                .foregroundColor(name.isEmpty ? .secondary : .accentColor)
                            
                            TextField("任务名称（留空自动命名为「\(previewDefaultName)」）", text: $name)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                            
                            if !name.isEmpty {
                                Button(action: { name = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary.opacity(0.8))
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .glassPanel(cornerRadius: 8)
                        
                        // 触发方式与时间选择
                        timePickerSection
                        
                        // 到期动作
                        actionSection
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                }
                
                Divider()
                    .opacity(0.2)
                
                // 3. 规范聚合底栏：左侧状态提示，右侧标准操作
                HStack(spacing: 10) {
                    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.orange.opacity(0.85))
                            Text("默认: \(previewDefaultName)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    Button("取消") {
                        stopPreview()
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    
                    Button(editingTask == nil ? "创建任务" : "保存修改") {
                        saveAndDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaveDisabled)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
            }
        }
        .frame(width: 480, height: dynamicHeight)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: actionTypeIndex)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: triggerMode)
        .onAppear {
            populateData()
        }
    }
    
    // 简明精炼的默认名称
    private var previewDefaultName: String {
        switch actionTypeIndex {
        case 1:
            return popupModeIndex == 0 ? "待办清单" : "今日日程"
        case 2:
            return audioDisplayName.isEmpty ? "播放音频" : audioDisplayName
        case 3:
            let clean = urlString.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
            return clean.isEmpty ? "打开链接" : clean
        default:
            if let inlineDate { return inlineDate.formatted(date: .omitted, time: .shortened) + " 提醒" }
            switch triggerMode {
            case 0:
                let total = countdownMinutes * 60 + countdownSeconds
                return total >= 60 ? "\(countdownMinutes) 分钟" : "\(total) 秒"
            case 1:
                return String(format: "%02d:%02d 提醒", dailyHour, dailyMinute)
            case 2:
                let total = intervalMinutes * 60 + intervalSeconds
                if total < 60 {
                    return "每 \(total) 秒"
                }
                let m = total / 60
                let s = total % 60
                if m >= 60 && m % 60 == 0 && s == 0 {
                    return "每 \(m / 60) 小时"
                }
                return s == 0 ? "每 \(m) 分钟" : "每 \(m)分\(s)秒"
            default:
                return "新任务"
            }
        }
    }
    
    // MARK: - 时间选择器
    private var timePickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.accentColor)
                Text("触发时机")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            Picker("", selection: $triggerMode) {
                if case .once = editingTask?.trigger { Text("一次提醒").tag(3) }
                Text("倒计时").tag(0)
                Text("每日定时").tag(1)
                Text("循环间隔").tag(2)
            }
            .pickerStyle(.segmented)
            
            VStack(spacing: 10) {
                if triggerMode == 3 {
                    DatePicker("提醒时间", selection: $onceDate, displayedComponents: [.date, .hourAndMinute])
                } else if triggerMode == 0 {
                    countdownInteractivePicker
                } else if triggerMode == 1 {
                    dailyTimeInteractivePicker
                } else {
                    intervalInteractivePicker
                }
            }
            .padding(12)
            .glassCard(cornerRadius: 10)
        }
    }
    
    // 统一样式的预设胶囊（柔和 Accent 描边，包容神经多样性人群视觉舒适度）
    private func presetPill(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    isSelected
                        ? Color.accentColor.opacity(0.18)
                        : Color.primary.opacity(0.04)
                )
                .foregroundColor(isSelected ? .accentColor : .primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isSelected ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.1),
                            lineWidth: 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
    
    // 1. 倒计时交互选择器 (极简双层结构)
    private var countdownInteractivePicker: some View {
        VStack(spacing: 14) {
            // 常用预设快捷胶囊
            HStack(spacing: 8) {
                ForEach([(5, "5m 快速"), (15, "15m"), (25, "25m 常用"), (45, "45m"), (60, "1h")], id: \.0) { mins, label in
                    let isSelected = countdownMinutes == mins && countdownSeconds == 0
                    presetPill(label: label, isSelected: isSelected) {
                        countdownMinutes = mins
                        countdownSeconds = 0
                    }
                }
            }
            
            // 核心数值调控区 (左右极简对称步进)
            HStack(spacing: 12) {
                Spacer()
                
                Button(action: { adjustCountdownMinutes(by: -5) }) {
                    Text("-5m")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 38, height: 30)
                        .glassPanel(cornerRadius: 7)
                }
                .buttonStyle(.plain)
                .help("减少 5 分钟")
                
                Button(action: { adjustCountdownMinutes(by: -1) }) {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 30, height: 30)
                        .glassPanel(cornerRadius: 7)
                }
                .buttonStyle(.plain)
                .help("减少 1 分钟")
                
                // 大字号时间展示
                HStack(spacing: 2) {
                    Text(String(format: "%02d", countdownMinutes))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(":")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(String(format: "%02d", countdownSeconds))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .padding(.horizontal, 12)
                
                Button(action: { adjustCountdownMinutes(by: 1) }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 30, height: 30)
                        .glassPanel(cornerRadius: 7)
                }
                .buttonStyle(.plain)
                .help("增加 1 分钟")
                
                Button(action: { adjustCountdownMinutes(by: 5) }) {
                    Text("+5m")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 38, height: 30)
                        .glassPanel(cornerRadius: 7)
                }
                .buttonStyle(.plain)
                .help("增加 5 分钟")
                
                Spacer()
            }
            .padding(.vertical, 2)
            
            // 秒数微调 (仅当存在秒数时低噪呈现，支持一键归零)
            if countdownSeconds > 0 {
                HStack(spacing: 6) {
                    Spacer()
                    Text("当前包含 \(countdownSeconds) 秒")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Button("秒数归零") {
                        countdownSeconds = 0
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.accentColor)
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
        }
    }
    
    private func adjustCountdownMinutes(by delta: Int) {
        countdownMinutes = max(1, min(300, countdownMinutes + delta))
    }
    
    // 2. 每日定时交互选择器 (原生高效体验)
    private var dailyTimeInteractivePicker: some View {
        VStack(spacing: 14) {
            // 常用时刻预设胶囊 (单行均分平铺)
            HStack(spacing: 8) {
                ForEach([(9, 0, "09:00 开工"), (12, 0, "12:00 午餐"), (14, 0, "14:00 提神"), (18, 0, "18:00 下班")], id: \.2) { h, m, label in
                    let isSelected = dailyHour == h && dailyMinute == m
                    presetPill(label: label, isSelected: isSelected) {
                        setDaily(hour: h, minute: m)
                    }
                }
            }
            
            // 原生时间输入器 (居中放大展示，支持直接键入数字与上下箭头键)
            HStack {
                Spacer()
                DatePicker("", selection: $dailyPickerDate, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.stepperField)
                    .labelsHidden()
                    .scaleEffect(1.2)
                    .onChange(of: dailyPickerDate) { newDate in
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                        dailyHour = comps.hour ?? 9
                        dailyMinute = comps.minute ?? 0
                    }
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }
    
    // 3. 循环间隔交互选择器 (支持分秒双调控)
    private var intervalInteractivePicker: some View {
        VStack(spacing: 14) {
            // 常用快捷胶囊 (覆盖秒级快闪与常用分钟)
            HStack(spacing: 6) {
                ForEach([
                    (0, 30, "30s"),
                    (1, 0, "1m 快速"),
                    (5, 0, "5m 间隙"),
                    (15, 0, "15m 护眼"),
                    (30, 0, "30m 喝水"),
                    (60, 0, "1h 休息")
                ], id: \.2) { m, s, label in
                    let isSelected = intervalMinutes == m && intervalSeconds == s
                    presetPill(label: label, isSelected: isSelected) {
                        intervalMinutes = m
                        intervalSeconds = s
                    }
                }
            }
            
            // 核心数值调控区 (左右对称微调)
            HStack(spacing: 10) {
                Spacer()
                
                Button(action: { adjustInterval(by: -10) }) {
                    Text("-10s")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 38, height: 30)
                        .glassPanel(cornerRadius: 7)
                }
                .buttonStyle(.plain)
                .help("减少 10 秒")
                
                Button(action: { adjustInterval(by: -60) }) {
                    Text("-1m")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 34, height: 30)
                        .glassPanel(cornerRadius: 7)
                }
                .buttonStyle(.plain)
                .help("减少 1 分钟")
                
                // 大字号时间展示
                HStack(spacing: 2) {
                    Text(String(format: "%02d", intervalMinutes))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(":")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(String(format: "%02d", intervalSeconds))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                
                Button(action: { adjustInterval(by: 60) }) {
                    Text("+1m")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 34, height: 30)
                        .glassPanel(cornerRadius: 7)
                }
                .buttonStyle(.plain)
                .help("增加 1 分钟")
                
                Button(action: { adjustInterval(by: 10) }) {
                    Text("+10s")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 38, height: 30)
                        .glassPanel(cornerRadius: 7)
                }
                .buttonStyle(.plain)
                .help("增加 10 秒")
                
                Spacer()
            }
            .padding(.vertical, 2)
            
            // 语义化清晰提示
            Text("每 \(intervalDisplay) 循环提醒一次")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
    
    private func adjustInterval(by seconds: Int) {
        let currentTotal = intervalMinutes * 60 + intervalSeconds
        let newTotal = max(5, min(86400, currentTotal + seconds))
        intervalMinutes = newTotal / 60
        intervalSeconds = newTotal % 60
    }
    
    private var intervalDisplay: String {
        let total = intervalMinutes * 60 + intervalSeconds
        if total < 60 {
            return "\(total) 秒"
        }
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            var res = "\(h) 小时"
            if m > 0 { res += " \(m) 分钟" }
            if s > 0 { res += " \(s) 秒" }
            return res
        } else {
            return s == 0 ? "\(m) 分钟" : "\(m)分\(s)秒"
        }
    }
    
    private func setDaily(hour: Int, minute: Int) {
        dailyHour = hour
        dailyMinute = minute
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        if let d = Calendar.current.date(from: comps) {
            dailyPickerDate = d
        }
    }
    
    private func addDailyOffset(minutes: Int) {
        let target = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let comps = Calendar.current.dateComponents([.hour, .minute], from: target)
        setDaily(hour: comps.hour ?? 9, minute: comps.minute ?? 0)
    }
    
    private var isSaveDisabled: Bool {
        if !validTime || (inlineDate.map { $0 <= Date() } ?? false) { return true }
        if inlineDate == nil && triggerMode == 3 && onceDate <= Date() { return true }
        if triggerMode == 0 && (countdownMinutes * 60 + countdownSeconds) <= 0 { return true }
        if triggerMode == 2 && (intervalMinutes * 60 + intervalSeconds) < 5 { return true }
        if actionTypeIndex == 2 && audioPath.isEmpty { return true }
        if actionTypeIndex == 3 && urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return false
    }
    
    // MARK: - 清单 / 日程设置区 (精炼文案)
    private var checklistConfigView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $popupModeIndex) {
                Text("待办清单").tag(0)
                Text("今日日程").tag(1)
            }
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()
            .font(.system(size: 11))
            
            if popupModeIndex == 0 {
                VStack(spacing: 6) {
                    HStack {
                        TextField("添加清单项 (按回车)", text: $newChecklistText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addChecklistItem() }
                        Button("添加") { addChecklistItem() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(newChecklistText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(checklistItems) { item in
                                HStack {
                                    Image(systemName: "circle")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Text(item.text)
                                        .font(.system(size: 12))
                                    Spacer()
                                    Button(action: {
                                        checklistItems.removeAll { $0.id == item.id }
                                    }) {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.red.opacity(0.7))
                                            .font(.system(size: 12))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .glassPanel(cornerRadius: 6)
                            }
                        }
                    }
                    .frame(height: 70)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundColor(.accentColor)
                    Text("到期自动展示当日的日历日程与提醒事项待办。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .glassPanel(cornerRadius: 6)
            }
        }
        .padding(10)
        .glassCard(cornerRadius: 8)
    }
    
    private func addChecklistItem() {
        let trimmed = newChecklistText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        checklistItems.append(ChecklistItem(text: trimmed))
        newChecklistText = ""
    }
    
    // MARK: - 音频配置
    private var localAudioConfigView: some View {
        VStack(spacing: 8) {
            // 预设音频快捷选择
            HStack(spacing: 8) {
                Text("快捷预设:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                let isEye = audioDisplayName == "眼保健操"
                Button(action: {
                    self.audioPath = "Resources/Audio/眼保健操.mp3"
                    self.audioDisplayName = "眼保健操"
                    if self.name.isEmpty { self.name = "护眼" }
                    if isPreviewing { stopPreview() }
                }) {
                    Text("👀 眼保健操")
                        .font(.system(size: 11, weight: isEye ? .bold : .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isEye ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
                        .foregroundColor(isEye ? .accentColor : .primary)
                        .overlay(
                            Capsule().stroke(isEye ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                
                let isBa = audioDisplayName == "健身气功八段锦口令"
                Button(action: {
                    self.audioPath = "Resources/Audio/健身气功八段锦口令.mp3"
                    self.audioDisplayName = "健身气功八段锦口令"
                    if self.name.isEmpty { self.name = "八段锦" }
                    if isPreviewing { stopPreview() }
                }) {
                    Text("🧘 八段锦")
                        .font(.system(size: 11, weight: isBa ? .bold : .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isBa ? Color.teal.opacity(0.2) : Color.primary.opacity(0.05))
                        .foregroundColor(isBa ? .teal : .primary)
                        .overlay(
                            Capsule().stroke(isBa ? Color.teal.opacity(0.6) : Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            
            HStack(spacing: 10) {
                Image(systemName: "music.note")
                    .foregroundColor(audioPath.isEmpty ? .secondary : .accentColor)
                Text(audioPath.isEmpty ? "拖拽音频到此处，或点击选择" : audioDisplayName)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer()
                Button("选择...") { selectLocalFile() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4])))
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { handleDropFiles(providers: $0) }
            
            HStack(spacing: 12) {
                Button(action: togglePreview) {
                    Label(isPreviewing ? "停止" : "试听", systemImage: isPreviewing ? "stop.fill" : "play.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(audioPath.isEmpty)
                
                Spacer()
                
                Slider(value: $audioVolume, in: 0...1.0)
                    .frame(width: 80)
                    .scaleEffect(0.85)
                
                Toggle("循环", isOn: $audioLoop)
                    .font(.system(size: 12))
            }
        }
        .padding(10)
        .glassCard(cornerRadius: 8)
    }
    
    // MARK: - URL 配置
    private var urlConfigView: some View {
        HStack {
            TextField("网址 (例如: zoom.us)", text: $urlString)
                .textFieldStyle(.roundedBorder)
            Button("测试") {
                let (url, _) = ScheduleTask.sanitizeURLString(urlString)
                if let u = url { NSWorkspace.shared.open(u) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .glassCard(cornerRadius: 8)
    }
    
    // MARK: - 辅助逻辑
    private func handleDropFiles(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                self.audioPath = url.path
                self.audioDisplayName = url.lastPathComponent
                if self.name.isEmpty { self.name = url.deletingPathExtension().lastPathComponent }
            }
        }
        return true
    }
    
    private func selectLocalFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio, .mp3, .wav, .aiff, UTType(filenameExtension: "m4a") ?? .audio]
        if panel.runModal() == .OK, let url = panel.url {
            self.audioPath = url.path
            self.audioDisplayName = url.lastPathComponent
            if self.name.isEmpty { self.name = url.deletingPathExtension().lastPathComponent }
        }
    }
    
    private func togglePreview() {
        if isPreviewing {
            stopPreview()
        } else {
            guard !audioPath.isEmpty else { return }
            audioService.playLocalFile(
                atPath: audioPath,
                displayName: audioDisplayName,
                loop: false,
                volume: audioVolume,
                durationSeconds: 20,
                fadeIn: false
            )
        }
    }
    
    private func stopPreview() {
        audioService.stop(fadeOut: false)
    }
    
    private func populateData() {
        guard let task = editingTask else {
            name = ""
            actionTypeIndex = 0
            return
        }
        
        name = task.name
        switch task.trigger {
        case .once(let date):
            triggerMode = 3
            onceDate = date
        case .countdown(let totalSeconds):
            triggerMode = 0
            countdownMinutes = totalSeconds / 60
            countdownSeconds = totalSeconds % 60
        case .daily(let hour, let minute):
            triggerMode = 1
            setDaily(hour: hour, minute: minute)
        case .interval(let totalSec):
            triggerMode = 2
            intervalMinutes = totalSec / 60
            intervalSeconds = totalSec % 60
        }
        
        switch task.action {
        case .none:
            actionTypeIndex = 0
        case .popupContent(let mode):
            actionTypeIndex = 1
            switch mode {
            case .textNotification:
                popupModeIndex = 0
            case .customChecklist(let items):
                popupModeIndex = 0
                checklistItems = items
            case .todaySystemAgenda:
                popupModeIndex = 1
            }
        case .playLocalAudio(let path, let displayName, let loop, let volume, let duration):
            actionTypeIndex = 2
            audioPath = path
            audioDisplayName = displayName
            audioLoop = loop
            audioVolume = volume
            if let d = duration {
                hasDurationLimit = true
                durationLimitMinutes = max(1, d / 60)
            }
        case .openURL(let url):
            actionTypeIndex = 3
            urlString = url
        }
    }
    
    private func saveAndDismiss() {
        stopPreview()
        
        guard !isSaveDisabled else { return }
        var trigger: TriggerType
        switch triggerMode {
        case 0:
            let total = max(1, countdownMinutes * 60 + countdownSeconds)
            trigger = .countdown(totalSeconds: total)
        case 1:
            trigger = .daily(hour: dailyHour, minute: dailyMinute)
        case 2:
            let total = max(5, intervalMinutes * 60 + intervalSeconds)
            trigger = .interval(intervalSeconds: total)
        case 3:
            trigger = .once(onceDate)
        default:
            trigger = .countdown(totalSeconds: 15 * 60)
        }
        
        if let inlineDate { trigger = .once(inlineDate) }
        let action: ActionType
        switch actionTypeIndex {
        case 0:
            action = .none
        case 1:
            let mode: PopupContentMode = (popupModeIndex == 0) ? .customChecklist(items: checklistItems) : .todaySystemAgenda
            action = .popupContent(mode: mode)
        case 2:
            let duration = hasDurationLimit ? (durationLimitMinutes * 60) : nil
            action = .playLocalAudio(filePath: audioPath, displayName: audioDisplayName.isEmpty ? (audioPath as NSString).lastPathComponent : audioDisplayName, loop: audioLoop, volume: audioVolume, durationSeconds: duration)
        case 3:
            let (_, sanitized) = ScheduleTask.sanitizeURLString(urlString)
            action = .openURL(urlString: sanitized)
        default:
            action = .none
        }
        
        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? previewDefaultName : name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        var task = editingTask ?? ScheduleTask(
            name: finalName,
            trigger: trigger,
            action: action,
            isEnabled: true
        )
        task.name = finalName
        task.trigger = trigger
        task.action = action
        if case .countdown(let secs) = trigger {
            task.countdownRemainingSeconds = secs
        }
        
        if let onSave = onSave {
            onSave(task)
        } else {
            if editingTask != nil {
                scheduler.updateTask(task)
            } else {
                scheduler.addTask(task)
            }
        }
        
        if inlineDate == nil { dismiss() }
    }
}
