import AppKit
import CoreGraphics
import Foundation

func generatePhotorealisticMacBook() {
    let canvasWidth: CGFloat = 2400
    let canvasHeight: CGFloat = 1500
    
    guard let context = CGContext(
        data: nil,
        width: Int(canvasWidth),
        height: Int(canvasHeight),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Failed to create CGContext")
    }

    let inputPath = "docs/assets/screenshots/real-desktop.jpg"
    guard let screenData = try? Data(contentsOf: URL(fileURLWithPath: inputPath)),
          let screenSource = CGImageSourceCreateWithData(screenData as CFData, nil),
          let userScreenCGImage = CGImageSourceCreateImageAtIndex(screenSource, 0, nil) else {
        fatalError("Failed to load \(inputPath)")
    }

    // 屏幕实际像素比例
    let screenAspect = CGFloat(userScreenCGImage.width) / CGFloat(userScreenCGImage.height) // 1024 / 639 ≈ 1.6025
    
    // 工业级参数
    let screenWidth: CGFloat = 1720
    let screenHeight: CGFloat = screenWidth / screenAspect // ≈ 1073.3
    let bezel: CGFloat = 16
    let outerWidth: CGFloat = screenWidth + bezel * 2
    let outerHeight: CGFloat = screenHeight + bezel * 2
    let outerRadius: CGFloat = 28
    
    let outerX = (canvasWidth - outerWidth) / 2
    let outerY: CGFloat = 260
    
    let baseWidth: CGFloat = outerWidth + 160
    let baseHeight: CGFloat = 24
    let baseX = (canvasWidth - baseWidth) / 2
    let baseY = outerY - 14

    // 1. 真实桌面多层环境光与接触阴影 (Ground Floor Shadows)
    context.saveGState()
    // 接触阴影 (Contact Shadow, 极深且紧贴底座)
    let contactRect = CGRect(x: baseX + 30, y: baseY - 12, width: baseWidth - 60, height: 20)
    context.addEllipse(in: contactRect)
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.28))
    context.setShadow(offset: CGSize(width: 0, height: 6), blur: 16, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
    context.fillPath()
    
    // 漫反射远景阴影 (Diffuse Ambient Shadow, 柔和扩散)
    let diffuseRect = CGRect(x: baseX + 60, y: baseY - 70, width: baseWidth - 120, height: 90)
    context.addEllipse(in: diffuseRect)
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.08))
    context.setShadow(offset: CGSize(width: 0, height: 20), blur: 70, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.20))
    context.fillPath()
    context.restoreGState()

    // 2. 绘制机身铝合金底座 (Base Chassis)
    context.saveGState()
    let baseCorner: CGFloat = 10
    let baseRect = CGRect(x: baseX, y: baseY, width: baseWidth, height: baseHeight)
    let basePath = CGPath(roundedRect: baseRect, cornerWidth: baseCorner, cornerHeight: baseCorner, transform: nil)
    
    // 纯正阳极氧化铝深空灰真实金属拉丝质感渐变
    let baseColors = [
        CGColor(red: 0.88, green: 0.89, blue: 0.91, alpha: 1.0), // 顶边高光
        CGColor(red: 0.72, green: 0.73, blue: 0.76, alpha: 1.0), // 中部铝身
        CGColor(red: 0.54, green: 0.55, blue: 0.58, alpha: 1.0), // 底部阴暗面
        CGColor(red: 0.38, green: 0.39, blue: 0.42, alpha: 1.0)
    ] as CFArray
    let baseGrad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: baseColors, locations: [0.0, 0.25, 0.85, 1.0])!
    
    context.addPath(basePath)
    context.clip()
    context.drawLinearGradient(baseGrad, start: CGPoint(x: baseX, y: baseY + baseHeight), end: CGPoint(x: baseX, y: baseY), options: [])
    context.restoreGState()

    // 绘制底座金属上边缘发丝高光 (Edge Highlight)
    context.saveGState()
    context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.7))
    context.setLineWidth(1.0)
    context.move(to: CGPoint(x: baseX + baseCorner, y: baseY + baseHeight - 0.5))
    context.addLine(to: CGPoint(x: baseX + baseWidth - baseCorner, y: baseY + baseHeight - 0.5))
    context.strokePath()
    context.restoreGState()

    // 绘制底座开盖凹槽 (Thumb Notch)
    context.saveGState()
    let notchW: CGFloat = 160
    let notchH: CGFloat = 8
    let notchX = (canvasWidth - notchW) / 2
    let notchY = baseY + baseHeight - notchH
    let notchRect = CGRect(x: notchX, y: notchY, width: notchW, height: notchH)
    let notchPath = CGPath(roundedRect: notchRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
    context.addPath(notchPath)
    context.setFillColor(CGColor(red: 0.38, green: 0.39, blue: 0.42, alpha: 1.0))
    context.fillPath()
    // 凹槽内部上边缘暗阴影
    context.setStrokeColor(CGColor(red: 0.20, green: 0.21, blue: 0.23, alpha: 0.9))
    context.setLineWidth(1.2)
    context.move(to: CGPoint(x: notchX + 2, y: notchY + notchH - 1))
    context.addLine(to: CGPoint(x: notchX + notchW - 2, y: notchY + notchH - 1))
    context.strokePath()
    context.restoreGState()

    // 3. 屏幕下方的黑色转轴 (Hinge Strip)
    context.saveGState()
    let hingeW = outerWidth - 200
    let hingeH: CGFloat = 10
    let hingeRect = CGRect(x: (canvasWidth - hingeW) / 2, y: outerY - 2, width: hingeW, height: hingeH)
    context.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1.0))
    context.fill(hingeRect)
    context.restoreGState()

    // 4. 显示屏外壳 (Display Lid Shell)
    context.saveGState()
    let lidRect = CGRect(x: outerX, y: outerY, width: outerWidth, height: outerHeight)
    let lidPath = CGPath(roundedRect: lidRect, cornerWidth: outerRadius, cornerHeight: outerRadius, transform: nil)
    
    // 金属外框双层倒角
    let lidColors = [
        CGColor(red: 0.85, green: 0.86, blue: 0.88, alpha: 1.0),
        CGColor(red: 0.62, green: 0.63, blue: 0.66, alpha: 1.0)
    ] as CFArray
    let lidGrad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: lidColors, locations: [0.0, 1.0])!
    context.addPath(lidPath)
    context.clip()
    context.drawLinearGradient(lidGrad, start: CGPoint(x: outerX, y: outerY + outerHeight), end: CGPoint(x: outerX, y: outerY), options: [])
    context.restoreGState()

    // 5. 屏幕黑色边框 (Black Bezel)
    context.saveGState()
    let bezelRect = lidRect.insetBy(dx: 3.5, dy: 3.5)
    let bezelPath = CGPath(roundedRect: bezelRect, cornerWidth: outerRadius - 2, cornerHeight: outerRadius - 2, transform: nil)
    context.addPath(bezelPath)
    context.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1.0))
    context.fillPath()

    // 6. 纯净屏幕玻璃显示区 (Active Retina Display)
    let screenRect = CGRect(x: outerX + bezel, y: outerY + bezel, width: screenWidth, height: screenHeight)
    let screenRadius: CGFloat = 12
    let screenPath = CGPath(roundedRect: screenRect, cornerWidth: screenRadius, cornerHeight: screenRadius, transform: nil)
    
    context.saveGState()
    context.addPath(screenPath)
    context.clip()

    // 绘制用户上传的真实原版截图 (无缝充满整个视网膜屏幕)
    context.draw(userScreenCGImage, in: screenRect)

    // 7. 屏幕微光泽层 (Subtle Glass Reflection) - 极度逼真的关键
    let glossColors = [
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.04),
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0)
    ] as CFArray
    let glossGrad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: glossColors, locations: [0.0, 1.0])!
    context.drawLinearGradient(glossGrad, start: CGPoint(x: screenRect.minX, y: screenRect.maxY), end: CGPoint(x: screenRect.maxX, y: screenRect.minY), options: [])
    
    context.restoreGState()

    // 8. 顶部 FaceTime HD 摄像头 (Camera Lens)
    let camRadius: CGFloat = 3.5
    let camCenter = CGPoint(x: lidRect.midX, y: screenRect.maxY + (bezel / 2))
    context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0))
    context.fillEllipse(in: CGRect(x: camCenter.x - camRadius, y: camCenter.y - camRadius, width: camRadius * 2, height: camRadius * 2))
    // 极小反光点
    context.setFillColor(CGColor(red: 0.25, green: 0.45, blue: 0.85, alpha: 0.7))
    context.fillEllipse(in: CGRect(x: camCenter.x - 1, y: camCenter.y - 1, width: 2, height: 2))

    context.restoreGState()

    // 9. 导出超高保真真机大图
    guard let finalImage = context.makeImage() else {
        fatalError("Failed to render final CGImage")
    }
    
    let destPath = "docs/assets/screenshots/macbook-mockup.png"
    let rootPath = "assets/screenshots/macbook-mockup.png"
    let destURL = URL(fileURLWithPath: destPath)
    
    guard let destination = CGImageDestinationCreateWithURL(destURL as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("Failed to create destination")
    }
    CGImageDestinationAddImage(destination, finalImage, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Failed to finalize PNG")
    }
    
    try? FileManager.default.removeItem(atPath: rootPath)
    try? FileManager.default.copyItem(atPath: destPath, toPath: rootPath)
    print("✅ 工业级逼真 MacBook 样机已合成输出至: \(destPath)")
}

generatePhotorealisticMacBook()
