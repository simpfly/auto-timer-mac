import AppKit
import CoreGraphics

func drawRaycastStyleIcon() -> NSImage {
    let size = NSSize(width: 1024, height: 1024)
    let image = NSImage(size: size)
    
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    
    // 1. 标准 macOS 图标画布 Squircle 矩形 (824x824, 留 100pt 边距适配标准阴影)
    let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let cornerRadius: CGFloat = 185
    let squirclePath = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    
    // 2. 底层轻柔阴影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 36, color: NSColor(calibratedWhite: 0.0, alpha: 0.55).cgColor)
    ctx.addPath(squirclePath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    
    // 3. 裁剪进入 Squircle 内部
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    
    // 3.1 Raycast 标志性深曜石黑背景 (极为深邃的暗黑微妙渐变 #131418 -> #0A0A0C)
    let bgColors = [
        NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.12, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.04, green: 0.04, blue: 0.05, alpha: 1.0).cgColor
    ] as CFArray
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(bgGradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    }
    
    // 3.2 中心极弱的环境漫反射光晕（Raycast 红色微晕）
    let glowColors = [
        NSColor(calibratedRed: 1.0, green: 0.25, blue: 0.25, alpha: 0.08).cgColor,
        NSColor.clear.cgColor
    ] as CFArray
    if let glowGradient = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(glowGradient, startCenter: CGPoint(x: 512, y: 512), startRadius: 10, endCenter: CGPoint(x: 512, y: 512), endRadius: 380, options: [])
    }
    
    // 4. Raycast 风格核心极简几何符号：
    // 由一个现代极简的「开放式定时刻度圆环」与一根「45° 锋利鲜红发光光线 (Ray)」构成！
    let center = CGPoint(x: 512, y: 512)
    let ringRadius: CGFloat = 220
    
    // 4.1 极简暗灰底环 (Clock Ring Track)
    ctx.saveGState()
    ctx.setLineWidth(32)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(NSColor(calibratedWhite: 0.22, alpha: 0.45).cgColor)
    ctx.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()
    
    // 4.2 标志性 Raycast 鲜红霓虹色 (Vibrant Vermilion / Raycast Crimson)
    // 渐变: #FF6666 -> #FF2A2A
    let redStart = NSColor(calibratedRed: 1.0, green: 0.38, blue: 0.35, alpha: 1.0)
    let redEnd = NSColor(calibratedRed: 0.95, green: 0.12, blue: 0.16, alpha: 1.0)
    
    // 4.3 表盘激活光弧（顺时针从 12 点扫到 4 点方向）
    ctx.saveGState()
    ctx.setLineWidth(34)
    ctx.setLineCap(.round)
    // 漫反射红光投影
    ctx.setShadow(offset: .zero, blur: 28, color: NSColor(calibratedRed: 1.0, green: 0.2, blue: 0.2, alpha: 0.6).cgColor)
    let arcPath = CGMutablePath()
    arcPath.addArc(center: center, radius: ringRadius, startAngle: CGFloat.pi * 0.5, endAngle: -CGFloat.pi * 0.2, clockwise: true)
    ctx.addPath(arcPath)
    ctx.setStrokeColor(redStart.cgColor)
    ctx.strokePath()
    ctx.restoreGState()
    
    // 4.4 标志性 45° 几何光带指针 (The Ray / Pointer)
    // 从中心向 45° 角射出的圆角几何多边形，充满速度感与启动感
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 24, color: NSColor(calibratedRed: 0.95, green: 0.15, blue: 0.15, alpha: 0.7).cgColor)
    
    let rayLength: CGFloat = 165
    let rayThickness: CGFloat = 34
    
    // 构建 45° 旋转的中心指针
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: CGFloat.pi * 0.25) // 45度
    
    let rayRect = CGRect(x: -rayThickness / 2, y: -rayThickness / 2, width: rayThickness, height: rayLength)
    let rayPath = CGPath(roundedRect: rayRect, cornerWidth: rayThickness / 2, cornerHeight: rayThickness / 2, transform: nil)
    ctx.addPath(rayPath)
    ctx.clip()
    
    let rayColors = [redStart.cgColor, redEnd.cgColor] as CFArray
    if let rayGradient = CGGradient(colorsSpace: colorSpace, colors: rayColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(rayGradient, start: CGPoint(x: 0, y: rayLength), end: CGPoint(x: 0, y: -rayThickness), options: [])
    }
    ctx.restoreGState()
    
    // 4.5 极简中心轴心 (纯白亮点，极具科技聚焦点)
    ctx.saveGState()
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.setShadow(offset: .zero, blur: 10, color: NSColor.white.cgColor)
    ctx.addArc(center: center, radius: 14, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
    ctx.fillPath()
    ctx.restoreGState()
    
    // 5. 顶层极简微光边框 (Subtle inner stroke)
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.setLineWidth(2.0)
    ctx.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.12).cgColor)
    ctx.strokePath()
    ctx.restoreGState()
    
    ctx.restoreGState() // 还原 clip
    
    image.unlockFocus()
    return image
}

let icon = drawRaycastStyleIcon()
guard let tiff = icon.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    print("❌ 生成 PNG 失败")
    exit(1)
}

let outputPath = "/Users/curiosita/dev/auto-timer-mac/AppIcon_1024.png"
try? pngData.write(to: URL(fileURLWithPath: outputPath))
print("✅ 成功生成 Raycast 风格高清 1024x1024 图标: \(outputPath)")
