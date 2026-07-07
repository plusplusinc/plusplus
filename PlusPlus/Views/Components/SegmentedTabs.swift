import SwiftUI

/// v2 segmented control (green fill on the active tab).
struct SegmentedTabs: View {
    let options: [String]
    @Binding var selectedIndex: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    selectedIndex = index
                } label: {
                    Text(option)
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(selectedIndex == index ? Theme.onPrimary : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            selectedIndex == index ? Theme.primaryFill : .clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
            }
        }
        .padding(3)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.border))
    }
}
