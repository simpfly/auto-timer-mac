import SwiftUI

// MARK: - 清晰优雅的区域标题组件 (SectionHeaderView)
public struct SectionHeaderView: View {
    public let icon: String
    public let title: String
    public var count: Int? = nil
    public var accentColor: Color = .secondary
    
    public init(icon: String, title: String, count: Int? = nil, accentColor: Color = .secondary) {
        self.icon = icon
        self.title = title
        self.count = count
        self.accentColor = accentColor
    }
    
    public var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(accentColor)
            
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
            
            if let c = count, c > 0 {
                let isNeutral = accentColor == .secondary
                Text("\(c)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(isNeutral ? .primary.opacity(0.65) : accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(isNeutral ? Color.primary.opacity(0.07) : accentColor.opacity(0.12))
                    .clipShape(Capsule())
            }
            
            Spacer()
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }
}
