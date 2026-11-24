import AppKit
import CoreGraphics
import Foundation

// MARK: - 创建 MacBook Pro 样机高清渲染图
func generateMacBookMockup() {
    let canvasWidth: CGFloat = 2000
    let canvasHeight: CGFloat = 1300
    
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
    
    let screenImageURL = URL(fileURLWithPath: "assets/screenshots/main-window.png")
    guard let screenData = try? Data(contentsOf: screenImageURL),
          let screenSource = CGImageSourceCreateWithData(screenData as CFData, nil),
          let appWindowCGImage = CGImageSourceCreateImageAtIndex(screenSource, 0, nil) else {
        fatalError("Failed to load assets/screenshots/main-window.png")
    }

    // 1. 样机几何参数
    let displayWidth: CGFloat = 1560
    let displayHeight: CGFloat = 990
    let displayX = (canvasWidth - displayWidth) / 2
    let displayY: CGFloat = 200
    let displayCornerRadius: CGFloat = 24
    let bezelWidth: CGFloat = 14
    
    let baseWidth: CGFloat = 1760
    let baseHeight: CGFloat = 26
    let baseX = (canvasWidth - baseWidth) / 2
    let baseY = displayY - 14

    // 2. 绘制地表柔和投影 (Contact Shadow)
    context.saveGState()
    let shadowRect = CGRect(x: baseX + 40, y: baseY - 60, width: baseWidth - 80, height: 70)
    let shadowPath = CGPath(ellipseIn: shadowRect, transform: nil)
    context.addPath(shadowPath)
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.14))
    context.setShadow(offset: CGSize(width: 0, height: 10), blur: 50, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.22))
    context.fillPath()
    context.restoreGState()

    // 3. 绘制底座金属下半身 (Base Chassis)
    context.saveGState()
    let basePath = CGMutablePath()
    let baseCorner: CGFloat = 12
    basePath.addRoundedRect(in: CGRect(x: baseX, y: baseY, width: baseWidth, height: baseHeight), cornerWidth: baseCorner, cornerHeight: baseCorner)
    
    // 铝合金深空灰微渐变
    let baseColors = [
        CGColor(red: 0.82, green: 0.83, blue: 0.85, alpha: 1.0),
        CGColor(red: 0.68, green: 0.69, blue: 0.72, alpha: 1.0),
        CGColor(red: 0.52, green: 0.53, blue: 0.56, alpha: 1.0)
    ] as CFArray
    let baseGradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: baseColors, locations: [0.0, 0.4, 1.0])!
    context.addPath(basePath)
    context.clip()
    context.drawLinearGradient(baseGradient, start: CGPoint(x: baseX, y: baseY + baseHeight), end: CGPoint(x: baseX, y: baseY), options: [])
    context.restoreGState()

    // 绘制底座中间的开盖凹槽 (Lid Notch)
    context.saveGState()
    let notchWidth: CGFloat = 140
    let notchHeight: CGFloat = 8
    let notchX = (canvasWidth - notchWidth) / 2
    let notchY = baseY + baseHeight - notchHeight
    let notchPath = CGMutablePath()
    notchPath.addRoundedRect(in: CGRect(x: notchX, y: notchY, width: notchWidth, height: notchHeight), cornerWidth: 4, cornerHeight: 4)
    context.addPath(notchPath)
    context.setFillColor(CGColor(red: 0.35, green: 0.36, blue: 0.38, alpha: 1.0))
    context.fillPath()
    context.restoreGState()

    // 4. 绘制显示屏上盖 (Display Lid Shell)
    context.saveGState()
    let lidRect = CGRect(x: displayX, y: displayY, width: displayWidth, height: displayHeight)
    let lidPath = CGPath(roundedRect: lidRect, cornerWidth: displayCornerRadius, cornerHeight: displayCornerRadius, transform: nil)
    
    // 铝合金细腻高光外边框
    context.addPath(lidPath)
    let lidColors = [
        CGColor(red: 0.76, green: 0.77, blue: 0.80, alpha: 1.0),
        CGColor(red: 0.58, green: 0.59, blue: 0.62, alpha: 1.0)
    ] as CFArray
    let lidGradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: lidColors, locations: [0.0, 1.0])!
    context.saveGState()
    context.clip()
    context.drawLinearGradient(lidGradient, start: CGPoint(x: displayX, y: displayY + displayHeight), end: CGPoint(x: displayX, y: displayY), options: [])
    context.restoreGState()

    // 5. 绘制屏幕黑色边框 (Black Bezel)
    let screenOuterRect = lidRect.insetBy(dx: 4, dy: 4)
    let screenOuterPath = CGPath(roundedRect: screenOuterRect, cornerWidth: displayCornerRadius - 3, cornerHeight: displayCornerRadius - 3, transform: nil)
    context.addPath(screenOuterPath)
    context.setFillColor(CGColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1.0))
    context.fillPath()

    // 6. 绘制纯净屏幕显示区 (Active Screen Area)
    let screenInnerRect = screenOuterRect.insetBy(dx: bezelWidth, dy: bezelWidth)
    let screenInnerPath = CGPath(roundedRect: screenInnerRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
    
    context.saveGState()
    context.addPath(screenInnerPath)
    context.clip()

    // 屏幕桌面壁纸：苹果优雅浅色渐变 (Sonoma / Studio Clean Light)
    let wallpaperColors = [
        CGColor(red: 0.94, green: 0.95, blue: 0.98, alpha: 1.0),
        CGColor(red: 0.88, green: 0.90, blue: 0.95, alpha: 1.0),
        CGColor(red: 0.82, green: 0.85, blue: 0.92, alpha: 1.0)
    ] as CFArray
    let wallpaperGrad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: wallpaperColors, locations: [0.0, 0.5, 1.0])!
    context.drawLinearGradient(wallpaperGrad, start: CGPoint(x: screenInnerRect.midX, y: screenInnerRect.maxY), end: CGPoint(x: screenInnerRect.midX, y: screenInnerRect.minY), options: [])

    // 绘制 macOS 顶栏 (Menu Bar)
    let menuBarHeight: CGFloat = 28
    let menuBarRect = CGRect(x: screenInnerRect.minX, y: screenInnerRect.maxY - menuBarHeight, width: screenInnerRect.width, height: menuBarHeight)
    context.setFillColor(CGColor(red: 0.98, green: 0.98, blue: 1.0, alpha: 0.85))
    context.fill(menuBarRect)
    
    // 顶栏微小苹果图标与菜单项
    context.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 0.7))
    context.fillEllipse(in: CGRect(x: menuBarRect.minX + 16, y: menuBarRect.midY - 4, width: 8, height: 8))

    // 绘制软件窗口截图 (居中安放)
    let windowAspect = CGFloat(appWindowCGImage.width) / CGFloat(appWindowCGImage.height)
    let appWindowHeight = screenInnerRect.height * 0.86
    let appWindowWidth = appWindowHeight * windowAspect
    let appWindowX = screenInnerRect.midX - appWindowWidth / 2
    let appWindowY = screenInnerRect.midY - appWindowHeight / 2 - 8
    let appRect = CGRect(x: appWindowX, y: appWindowY, width: appWindowWidth, height: appWindowHeight)
    
    context.draw(appWindowCGImage, in: appRect)
    context.restoreGState()

    // 7. 顶部刘海/微型摄像头 (FaceTime Camera)
    let camRadius: CGFloat = 3.5
    let camCenter = CGPoint(x: lidRect.midX, y: lidRect.maxY - bezelWidth / 2 - 2)
    context.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1.0))
    context.fillEllipse(in: CGRect(x: camCenter.x - camRadius, y: camCenter.y - camRadius, width: camRadius * 2, height: camRadius * 2))
    // 镜头微小蓝紫反光
    context.setFillColor(CGColor(red: 0.15, green: 0.25, blue: 0.55, alpha: 0.8))
    context.fillEllipse(in: CGRect(x: camCenter.x - 1.5, y: camCenter.y - 1.5, width: 3, height: 3))

    context.restoreGState()

    // 8. 导出高清 PNG
    guard let outputImage = context.makeImage() else {
        fatalError("Failed to create CGImage")
    }
    
    let destURL = URL(fileURLWithPath: "docs/assets/screenshots/macbook-mockup.png")
    let rootDestURL = URL(fileURLWithPath: "assets/screenshots/macbook-mockup.png")
    
    guard let destination = CGImageDestinationCreateWithURL(destURL as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("Failed to create CGImageDestination")
    }
    CGImageDestinationAddImage(destination, outputImage, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Failed to write to file")
    }
    
    // 同时同步到 root assets
    try? FileManager.default.copyItem(at: destURL, to: rootDestURL)
    
    print("✅ 成功生成 MacBook 硬件样机外壳截图：\(destURL.path)")
}

generateMacBookMockup()
