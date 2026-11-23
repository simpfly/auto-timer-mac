import AppKit
import SwiftUI

/// Shared monochrome brand mark. Template rendering follows menu bar appearance.
enum BrandIcon {
    static let menuBar: NSImage = {
        guard let url = Bundle.module.url(forResource: "MenuBarTemplate", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            assertionFailure("Missing menu bar brand asset")
            return NSImage(systemSymbolName: "timer", accessibilityDescription: "It's Time") ?? NSImage()
        }
        image.size = NSSize(width: 22, height: 22)
        image.isTemplate = true
        image.accessibilityDescription = "It's Time"
        return image
    }()
}

/// 统一复用的品牌标题组件：包含标准品牌图标与 "It's Time" 标题
struct BrandTitleView: View {
    var iconSize: CGFloat = 18
    var fontSize: CGFloat = 14
    var fontWeight: Font.Weight = .bold
    var foregroundColor: Color = .primary

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: BrandIcon.menuBar)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
                .foregroundColor(foregroundColor)
            
            Text("It's Time")
                .font(.system(size: fontSize, weight: fontWeight))
                .foregroundColor(foregroundColor)
        }
    }
}
