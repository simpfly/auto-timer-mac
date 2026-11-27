import SwiftUI

/// 全局快捷键入口只展示快捷输入，不包含任务列表和统计。
struct QuickReminderPopoverView: View {
    @ObservedObject private var statusManager = StatusItemManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                BrandTitleView()
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().opacity(0.25)

            QuickTaskCreateView(timelineWidth: 200, focusRequest: statusManager.quickReminderRequest)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 14)
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .disableFocusEffect()
    }
}
