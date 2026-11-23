import AppKit
import CoreGraphics

func drawLinearStyleIcon() -> NSImage {
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
    
    // 2. 底层纯净柔和阴影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 36, color: NSColor(calibratedWhite: 0.0, alpha: 0.6).cgColor)
    ctx.addPath(squirclePath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    
    // 3. 裁剪进入 Squircle 内部
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    
    // 3.1 Linear 标志性深邃暗黑底色 (#101216 -> #07080A)
    let bgColors = [
        NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.03, green: 0.03, blue: 0.04, alpha: 1.0).cgColor
    ] as CFArray
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(bgGradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    }
    
    // 3.2 极弱环境微光 (深蓝冷光环境)
    let center = CGPoint(x: 512, y: 512)
    let ambientColors = [
        NSColor(calibratedRed: 0.1, green: 0.35, blue: 0.8, alpha: 0.08).cgColor,
        NSColor.clear.cgColor
    ] as CFArray
    if let ambGrad = CGGradient(colorsSpace: colorSpace, colors: ambientColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(ambGrad, startCenter: center, startRadius: 10, endCenter: center, endRadius: 380, options: [])
    }
    
    let ringRadius: CGFloat = 225
    
    // 4.1 极简纤细轨道环 (Clock Track - 仅 14pt 宽，轻盈通透)
    ctx.saveGState()
    ctx.setLineWidth(14)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.10).cgColor)
    ctx.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()
    
    // 4.2 极简刻度微点 (12, 3, 6, 9 点钟位置的微点，精致若隐若现)
    for i in 0..<4 {
        let angle = CGFloat(i) * CGFloat.pi * 0.5
        let pt = CGPoint(x: center.x + cos(angle) * (ringRadius + 28), y: center.y + sin(angle) * (ringRadius + 28))
        ctx.saveGState()
        ctx.addArc(center: pt, radius: 4, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
        ctx.setFillColor(NSColor(calibratedWhite: 1.0, alpha: 0.25).cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }
    
    // 4.3 Linear 标志性高饱和流光渐变色:
    // 起点：纯净冷电青 #00F0FF (Electric Cyan)
    // 终点：深邃蔚蓝 #2E5BFF (Cobalt Royal Blue)
    let cyan = NSColor(calibratedRed: 0.0, green: 0.94, blue: 1.0, alpha: 1.0)
    let royalBlue = NSColor(calibratedRed: 0.18, green: 0.38, blue: 1.0, alpha: 1.0)
    
    // 4.4 激活光弧 (从 12 点顺时针扫至 3:30 方向)
    ctx.saveGState()
    ctx.setLineWidth(18)
    ctx.setLineCap(.round)
    // 柔和微光投影（纯净冷色，绝无刺眼杂边）
    ctx.setShadow(offset: .zero, blur: 22, color: cyan.withAlphaComponent(0.55).cgColor)
    let arcPath = CGMutablePath()
    arcPath.addArc(center: center, radius: ringRadius, startAngle: CGFloat.pi * 0.5, endAngle: -CGFloat.pi * 0.12, clockwise: true)
    ctx.addPath(arcPath)
    ctx.setStrokeColor(cyan.cgColor)
    ctx.strokePath()
    ctx.restoreGState()
    
    // 4.5 Linear 风格流线光针 (Precision Pointer)
    // 从中心向 55° 方向（两点钟方向）优雅射出的极简流线几何
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 18, color: royalBlue.withAlphaComponent(0.6).cgColor)
    
    let rayLength: CGFloat = 175
    let rayThickness: CGFloat = 20
    
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: CGFloat.pi * 0.30) // 指向两点钟偏上方向，极富动感
    
    let rayRect = CGRect(x: -rayThickness / 2, y: -rayThickness / 2, width: rayThickness, height: rayLength)
    let rayPath = CGPath(roundedRect: rayRect, cornerWidth: rayThickness / 2, cornerHeight: rayThickness / 2, transform: nil)
    ctx.addPath(rayPath)
    ctx.clip()
    
    let rayColors = [cyan.cgColor, royalBlue.cgColor] as CFArray
    if let rayGrad = CGGradient(colorsSpace: colorSpace, colors: rayColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(rayGrad, start: CGPoint(x: 0, y: rayLength), end: CGPoint(x: 0, y: -rayThickness), options: [])
    }
    ctx.restoreGState()
    
    // 4.6 极简中心轴心点 (纯白晶核，极小极凝练)
    ctx.saveGState()
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.setShadow(offset: .zero, blur: 8, color: NSColor.white.cgColor)
    ctx.addArc(center: center, radius: 10, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
    ctx.fillPath()
    ctx.restoreGState()
    
    // 5. 顶层克制极简内高光边框 (Subtle inner stroke)
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.setLineWidth(1.8)
    ctx.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.10).cgColor)
    ctx.strokePath()
    ctx.restoreGState()
    
    ctx.restoreGState()
    
    image.unlockFocus()
    return image
}

let icon = drawLinearStyleIcon()
guard let tiff = icon.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    print("❌ 生成 PNG 失败")
    exit(1)
}

let outputPath = "/Users/curiosita/dev/auto-timer-mac/preview_linear.png"
try? pngData.write(to: URL(fileURLWithPath: outputPath))
print("✅ 成功生成 Linear 风格极简高清图标: \(outputPath)")
