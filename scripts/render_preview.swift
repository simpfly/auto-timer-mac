import SwiftUI
import AppKit

struct DemoPill: View {
    let label: String
    let isSelected: Bool
    var tintColor: Color = .accentColor
    
    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
            .lineLimit(1)
            .foregroundColor(isSelected ? tintColor : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(isSelected ? tintColor.opacity(0.14) : Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct DemoStepper: View {
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "minus")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.primary.opacity(0.75))
                .frame(width: 20, height: 20)
                .background(Color.primary.opacity(0.06))
                .clipShape(Circle())
            
            Text(text)
                .font(.system(size: 13, weight: .regular))
                .frame(width: 48, height: 21)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.primary.opacity(0.75))
                .frame(width: 20, height: 20)
                .background(Color.primary.opacity(0.06))
                .clipShape(Circle())
        }
    }
}

struct MockPanel: View {
    let modeTitle: String
    let presets: [String]
    let selectedPreset: String
    let timeText: String
    let isDailyRepeat: Bool? // nil for countdown/interval
    let inputPlaceholder: String
    let tintColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 输入行
            HStack(spacing: 8) {
                HStack {
                    Text(inputPlaceholder)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.8)
                )
                
                // 提醒动作
                HStack(spacing: 4) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 10))
                    Text("文本提示")
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                
                // 开始按钮
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            
            // 模式切换行
            HStack(spacing: 6) {
                // 倒计时
                HStack(spacing: 3) {
                    Image(systemName: "timer").font(.system(size: 10))
                    Text("倒计时").font(.system(size: 11, weight: modeTitle == "倒计时" ? .semibold : .regular))
                }
                .foregroundColor(modeTitle == "倒计时" ? .white : .primary.opacity(0.8))
                .padding(.horizontal, 9).padding(.vertical, 4.5)
                .background(modeTitle == "倒计时" ? Color.blue : Color.primary.opacity(0.06))
                .clipShape(Capsule())
                
                // 定时提醒
                HStack(spacing: 3) {
                    Image(systemName: "clock").font(.system(size: 10))
                    Text("定时提醒").font(.system(size: 11, weight: modeTitle == "定时提醒" ? .semibold : .regular))
                }
                .foregroundColor(modeTitle == "定时提醒" ? .white : .primary.opacity(0.8))
                .padding(.horizontal, 9).padding(.vertical, 4.5)
                .background(modeTitle == "定时提醒" ? Color.blue : Color.primary.opacity(0.06))
                .clipShape(Capsule())
                
                // 循环间隔
                HStack(spacing: 3) {
                    Image(systemName: "repeat").font(.system(size: 10))
                    Text("循环间隔").font(.system(size: 11, weight: modeTitle == "循环间隔" ? .semibold : .regular))
                }
                .foregroundColor(modeTitle == "循环间隔" ? .white : .primary.opacity(0.8))
                .padding(.horizontal, 9).padding(.vertical, 4.5)
                .background(modeTitle == "循环间隔" ? Color.blue : Color.primary.opacity(0.06))
                .clipShape(Capsule())
                
                Spacer()
            }
            
            // 时长/预设控制行：
            // 【最左边：时间选择器】 + 【中间：快捷选项 3 个】 + 【最右边：重复设置】
            HStack(alignment: .center, spacing: 8) {
                // 1. 最左边：统一时间选择微调器
                DemoStepper(text: timeText)
                
                // 2. 中间：仅留 3 个快捷预设
                HStack(spacing: 5) {
                    ForEach(presets, id: \.self) { p in
                        DemoPill(label: p, isSelected: p == selectedPreset, tintColor: tintColor)
                    }
                }
                
                Spacer()
                
                // 3. 最右边：重复设置（定时提醒专属）
                if let isDailyRepeat = isDailyRepeat {
                    HStack(spacing: 4) {
                        Image(systemName: isDailyRepeat ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11))
                            .foregroundColor(isDailyRepeat ? .indigo : .secondary)
                        Text("每日重复")
                            .font(.system(size: 11, weight: isDailyRepeat ? .semibold : .medium))
                            .foregroundColor(isDailyRepeat ? .indigo : .secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isDailyRepeat ? Color.indigo.opacity(0.12) : Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

struct PreviewAll: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 标题
            VStack(alignment: .leading, spacing: 4) {
                Text("It's Time · 交互调整最新示意图")
                    .font(.system(size: 16, weight: .bold))
                Text("【最左】时间选择器  |  【中间】3 个快捷选项  |  【最右】重复设置")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)
            
            // 场景 1：定时提醒（单次，未勾选每日重复 - 默认）
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("场景 1：定时提醒（单次到期即止 · 默认状态）")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.indigo)
                    Spacer()
                    Text("左：时间选择器  中：3快捷  右：每日重复(未勾选)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                MockPanel(
                    modeTitle: "定时提醒",
                    presets: ["09:00", "14:00", "18:00"],
                    selectedPreset: "14:00",
                    timeText: "14:00",
                    isDailyRepeat: false,
                    inputPlaceholder: "14:00 提醒我（单次）",
                    tintColor: .indigo
                )
            }
            
            // 场景 2：定时提醒（勾选每日重复）
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("场景 2：定时提醒（选择「每日重复」后，每天重复）")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.indigo)
                    Spacer()
                    Text("右侧「每日重复」高亮激活")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                MockPanel(
                    modeTitle: "定时提醒",
                    presets: ["09:00", "14:00", "18:00"],
                    selectedPreset: "09:00",
                    timeText: "09:00",
                    isDailyRepeat: true,
                    inputPlaceholder: "每天 09:00 提醒我",
                    tintColor: .indigo
                )
            }
            
            // 场景 3：倒计时
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("场景 3：倒计时模式（时间选择器在最左，3 个快捷选项在旁）")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.blue)
                    Spacer()
                    Text("1m / 5m / 25m")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                MockPanel(
                    modeTitle: "倒计时",
                    presets: ["1m", "5m", "25m"],
                    selectedPreset: "25m",
                    timeText: "25:00",
                    isDailyRepeat: nil,
                    inputPlaceholder: "25分钟后提醒我",
                    tintColor: .blue
                )
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

let preview = PreviewAll()
let hosting = NSHostingView(rootView: preview)
let targetSize = hosting.fittingSize
hosting.frame = CGRect(origin: .zero, size: targetSize)

guard let bitmapRep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
    fatalError("Failed to get bitmapRep")
}
hosting.cacheDisplay(in: hosting.bounds, to: bitmapRep)

guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to convert to PNG")
}

let outputPath = "/Users/curiosita/dev/auto-timer-mac/preview_scheduled_reminder.png"
try pngData.write(to: URL(fileURLWithPath: outputPath))
print("Successfully generated preview image at: \(outputPath)")
