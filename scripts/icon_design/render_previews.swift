import AppKit
import CoreGraphics

func savePNG(image: NSImage, path: String) {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("❌ 保存失败: \(path)")
        return
    }
    try? pngData.write(to: URL(fileURLWithPath: path))
    print("✅ 已生成: \(path)")
}

let size = NSSize(width: 1024, height: 1024)
let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185
let squirclePath = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
let colorSpace = CGColorSpaceCreateDeviceRGB()

// ==========================================
// 方案 A: 极简流光时钟与声波 (Sleek Aurora & Sonic Chrono)
// ==========================================
func renderOptionA() -> NSImage {
    let img = NSImage(size: size)
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { img.unlockFocus(); return img }
    
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    
    // 阴影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 40, color: NSColor(calibratedRed: 0.02, green: 0.05, blue: 0.12, alpha: 0.65).cgColor)
    ctx.addPath(squirclePath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    
    // Squircle 剪裁
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()
    
    // 背景渐变：深邃星空靛蓝 -> 幽夜黑
    let bgColors = [
        NSColor(calibratedRed: 0.07, green: 0.11, blue: 0.20, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.08, alpha: 1.0).cgColor
    ] as CFArray
    if let grad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(grad, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    }
    
    // 柔和极光光晕 (Indigo / Cyan 漫射)
    let glowColors = [
        NSColor(calibratedRed: 0.15, green: 0.55, blue: 1.0, alpha: 0.18).cgColor,
        NSColor(calibratedRed: 0.45, green: 0.25, blue: 0.95, alpha: 0.10).cgColor,
        NSColor.clear.cgColor
    ] as CFArray
    if let glowGrad = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 0.5, 1.0]) {
        ctx.drawRadialGradient(glowGrad, startCenter: CGPoint(x: 512, y: 550), startRadius: 20, endCenter: CGPoint(x: 512, y: 550), endRadius: 420, options: [])
    }
    
    let center = CGPoint(x: 512, y: 512)
    let ringRadius: CGFloat = 230
    
    // 1. 底环轨道
    ctx.saveGState()
    ctx.setLineWidth(24)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(NSColor(calibratedRed: 0.2, green: 0.3, blue: 0.45, alpha: 0.25).cgColor)
    ctx.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()
    
    // 2. 刻度点 (12, 3, 6, 9)
    for i in 0..<12 {
        let angle = CGFloat(i) * CGFloat.pi / 6.0
        let r1: CGFloat = (i % 3 == 0) ? ringRadius - 26 : ringRadius - 20
        let r2: CGFloat = ringRadius - 12
        let p1 = CGPoint(x: center.x + cos(angle) * r1, y: center.y + sin(angle) * r1)
        let p2 = CGPoint(x: center.x + cos(angle) * r2, y: center.y + sin(angle) * r2)
        ctx.saveGState()
        ctx.setLineWidth(i % 3 == 0 ? 5 : 3)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(NSColor(calibratedRed: 0.5, green: 0.7, blue: 1.0, alpha: i % 3 == 0 ? 0.6 : 0.25).cgColor)
        ctx.move(to: p1)
        ctx.addLine(to: p2)
        ctx.strokePath()
        ctx.restoreGState()
    }
    
    // 3. 极光计时激活光弧 (从 12 点顺时针扫至 4 点方向)
    ctx.saveGState()
    ctx.setLineWidth(26)
    ctx.setLineCap(.round)
    ctx.setShadow(offset: .zero, blur: 32, color: NSColor(calibratedRed: 0.0, green: 0.85, blue: 1.0, alpha: 0.7).cgColor)
    let arcPath = CGMutablePath()
    arcPath.addArc(center: center, radius: ringRadius, startAngle: CGFloat.pi * 0.5, endAngle: -CGFloat.pi * 0.15, clockwise: true)
    ctx.addPath(arcPath)
    ctx.setStrokeColor(NSColor(calibratedRed: 0.0, green: 0.9, blue: 1.0, alpha: 1.0).cgColor)
    ctx.strokePath()
    ctx.restoreGState()
    
    // 4. 中心声波律动柱 (Soundwave Bars) - 象征定时音频与触发唤醒
    let barHeights: [CGFloat] = [70, 130, 190, 140, 80]
    let barWidth: CGFloat = 22
    let barSpacing: CGFloat = 40
    let totalWidth = CGFloat(barHeights.count - 1) * barSpacing
    let startX = center.x - totalWidth / 2.0
    
    for (idx, h) in barHeights.enumerated() {
        let x = startX + CGFloat(idx) * barSpacing
        let rect = CGRect(x: x - barWidth / 2.0, y: center.y - h / 2.0, width: barWidth, height: h)
        let barPath = CGPath(roundedRect: rect, cornerWidth: barWidth / 2.0, cornerHeight: barWidth / 2.0, transform: nil)
        
        ctx.saveGState()
        // 发光外晕
        ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 18, color: NSColor(calibratedRed: 0.2, green: 0.6, blue: 1.0, alpha: 0.65).cgColor)
        ctx.addPath(barPath)
        ctx.clip()
        
        // 蓝青渐变填充
        let barGradColors = [
            NSColor(calibratedRed: 0.1, green: 0.95, blue: 0.95, alpha: 1.0).cgColor,
            NSColor(calibratedRed: 0.35, green: 0.45, blue: 1.0, alpha: 1.0).cgColor
        ] as CFArray
        if let barGrad = CGGradient(colorsSpace: colorSpace, colors: barGradColors, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(barGrad, start: CGPoint(x: x, y: center.y + h / 2.0), end: CGPoint(x: x, y: center.y - h / 2.0), options: [])
        }
        ctx.restoreGState()
    }
    
    // 5. 顶层精致微光高光边框
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.setLineWidth(2.5)
    ctx.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.16).cgColor)
    ctx.strokePath()
    ctx.restoreGState()
    
    ctx.restoreGState()
    img.unlockFocus()
    return img
}

// ==========================================
// 方案 B: 纯净原生通透毛玻璃 (Apple Native Frosted Glass Ring)
// ==========================================
func renderOptionB() -> NSImage {
    let img = NSImage(size: size)
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { img.unlockFocus(); return img }
    
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    
    // 原生轻柔阴影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 36, color: NSColor(calibratedRed: 0.2, green: 0.25, blue: 0.35, alpha: 0.35).cgColor)
    ctx.addPath(squirclePath)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    
    // Squircle 剪裁
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()
    
    // 背景渐变：明亮纯净的浅天蓝/冰白
    let bgColors = [
        NSColor(calibratedRed: 0.96, green: 0.98, blue: 1.0, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.86, green: 0.91, blue: 0.96, alpha: 1.0).cgColor
    ] as CFArray
    if let grad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(grad, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    }
    
    // 内部悬浮玻璃圆盘底座
    let center = CGPoint(x: 512, y: 512)
    let discRadius: CGFloat = 300
    let discRect = CGRect(x: center.x - discRadius, y: center.y - discRadius, width: discRadius * 2, height: discRadius * 2)
    let discPath = CGPath(ellipseIn: discRect, transform: nil)
    
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor(calibratedRed: 0.4, green: 0.5, blue: 0.65, alpha: 0.25).cgColor)
    ctx.addPath(discPath)
    ctx.setFillColor(NSColor(calibratedWhite: 1.0, alpha: 0.85).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    
    // 玻璃圆盘微妙高光边缘
    ctx.saveGState()
    ctx.addPath(discPath)
    ctx.setLineWidth(3)
    ctx.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.9).cgColor)
    ctx.strokePath()
    ctx.restoreGState()
    
    // 计时主光环 (Apple 蓝色与紫色流转渐变)
    let ringRadius: CGFloat = 200
    
    // 背景浅灰槽
    ctx.saveGState()
    ctx.setLineWidth(28)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(NSColor(calibratedRed: 0.88, green: 0.91, blue: 0.95, alpha: 1.0).cgColor)
    ctx.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()
    
    // 激活光环 (从 12 点扫到 5 点)
    ctx.saveGState()
    ctx.setLineWidth(28)
    ctx.setLineCap(.round)
    ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 16, color: NSColor(calibratedRed: 0.0, green: 0.45, blue: 0.95, alpha: 0.45).cgColor)
    let arcB = CGMutablePath()
    arcB.addArc(center: center, radius: ringRadius, startAngle: CGFloat.pi * 0.5, endAngle: -CGFloat.pi * 0.35, clockwise: true)
    ctx.addPath(arcB)
    ctx.setStrokeColor(NSColor(calibratedRed: 0.0, green: 0.48, blue: 1.0, alpha: 1.0).cgColor)
    ctx.strokePath()
    ctx.restoreGState()
    
    // 中心原生指针：时针与分针 (极简圆角胶囊几何)
    // 分针 (指向 2 点方向, 60度)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 8, color: NSColor(calibratedWhite: 0.2, alpha: 0.2).cgColor)
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: CGFloat.pi / 6.0) // 30度
    let mHand = CGPath(roundedRect: CGRect(x: -8, y: -8, width: 16, height: 130), cornerWidth: 8, cornerHeight: 8, transform: nil)
    ctx.addPath(mHand)
    ctx.setFillColor(NSColor(calibratedRed: 0.15, green: 0.2, blue: 0.28, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    
    // 时针 (指向 10 点方向)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 8, color: NSColor(calibratedWhite: 0.2, alpha: 0.2).cgColor)
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: -CGFloat.pi / 2.8)
    let hHand = CGPath(roundedRect: CGRect(x: -11, y: -11, width: 22, height: 90), cornerWidth: 11, cornerHeight: 11, transform: nil)
    ctx.addPath(hHand)
    ctx.setFillColor(NSColor(calibratedRed: 0.0, green: 0.48, blue: 1.0, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    
    // 轴心
    ctx.saveGState()
    ctx.addArc(center: center, radius: 18, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 6, color: NSColor.black.withAlphaComponent(0.2).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    
    ctx.saveGState()
    ctx.addArc(center: center, radius: 8, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
    ctx.setFillColor(NSColor(calibratedRed: 0.0, green: 0.48, blue: 1.0, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    
    // 顶层微光边框
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.setLineWidth(2.0)
    ctx.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.8).cgColor)
    ctx.strokePath()
    ctx.restoreGState()
    
    ctx.restoreGState()
    img.unlockFocus()
    return img
}

// ==========================================
// 方案 C: 深曜石极光飞梭 (Obsidian Neon Pulse)
// ==========================================
func renderOptionC() -> NSImage {
    let img = NSImage(size: size)
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { img.unlockFocus(); return img }
    
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    
    // 阴影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 38, color: NSColor(calibratedWhite: 0.0, alpha: 0.6).cgColor)
    ctx.addPath(squirclePath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    
    // Squircle 剪裁
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()
    
    // 曜石暗夜背景
    let bgColors = [
        NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.14, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.06, alpha: 1.0).cgColor
    ] as CFArray
    if let grad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(grad, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    }
    
    // 翡翠绿/青电漫射光晕
    let glowColors = [
        NSColor(calibratedRed: 0.05, green: 0.85, blue: 0.65, alpha: 0.15).cgColor,
        NSColor.clear.cgColor
    ] as CFArray
    if let glowGrad = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(glowGrad, startCenter: CGPoint(x: 512, y: 512), startRadius: 10, endCenter: CGPoint(x: 512, y: 512), endRadius: 390, options: [])
    }
    
    let center = CGPoint(x: 512, y: 512)
    
    // 几何双环流转符号 (Mobius / Infinity 环与时钟融合)
    let leftCenter = CGPoint(x: center.x - 110, y: center.y)
    let rightCenter = CGPoint(x: center.x + 110, y: center.y)
    let r: CGFloat = 135
    
    // 底层灰轨
    ctx.saveGState()
    ctx.setLineWidth(32)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(NSColor(calibratedWhite: 0.22, alpha: 0.4).cgColor)
    ctx.addArc(center: leftCenter, radius: r, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
    ctx.strokePath()
    ctx.addArc(center: rightCenter, radius: r, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()
    
    // 霓虹极光流光 (薄荷绿 -> 电气青)
    let neonGreen = NSColor(calibratedRed: 0.05, green: 0.95, blue: 0.65, alpha: 1.0)
    let neonCyan = NSColor(calibratedRed: 0.0, green: 0.85, blue: 1.0, alpha: 1.0)
    
    ctx.saveGState()
    ctx.setLineWidth(34)
    ctx.setLineCap(.round)
    ctx.setShadow(offset: .zero, blur: 28, color: neonGreen.withAlphaComponent(0.65).cgColor)
    
    let infPath = CGMutablePath()
    // 左环激活光弧
    infPath.addArc(center: leftCenter, radius: r, startAngle: CGFloat.pi * 0.7, endAngle: -CGFloat.pi * 0.3, clockwise: true)
    ctx.addPath(infPath)
    ctx.setStrokeColor(neonGreen.cgColor)
    ctx.strokePath()
    ctx.restoreGState()
    
    ctx.saveGState()
    ctx.setLineWidth(34)
    ctx.setLineCap(.round)
    ctx.setShadow(offset: .zero, blur: 28, color: neonCyan.withAlphaComponent(0.65).cgColor)
    
    let infPathR = CGMutablePath()
    // 右环激活光弧
    infPathR.addArc(center: rightCenter, radius: r, startAngle: -CGFloat.pi * 0.3, endAngle: CGFloat.pi * 0.7, clockwise: true)
    ctx.addPath(infPathR)
    ctx.setStrokeColor(neonCyan.cgColor)
    ctx.strokePath()
    ctx.restoreGState()
    
    // 中心脉冲光点 (连接处交汇白核)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 16, color: NSColor.white.cgColor)
    ctx.addArc(center: center, radius: 14, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    
    // 顶层微光边框
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.setLineWidth(2.0)
    ctx.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor)
    ctx.strokePath()
    ctx.restoreGState()
    
    ctx.restoreGState()
    img.unlockFocus()
    return img
}

savePNG(image: renderOptionA(), path: "/Users/curiosita/dev/auto-timer-mac/preview_option_a.png")
savePNG(image: renderOptionB(), path: "/Users/curiosita/dev/auto-timer-mac/preview_option_b.png")
savePNG(image: renderOptionC(), path: "/Users/curiosita/dev/auto-timer-mac/preview_option_c.png")
print("🎉 三套方案渲染完成！")
