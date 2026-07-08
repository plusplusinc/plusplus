import SwiftUI

/// Segmented control in the selection grammar: the active tab is a
/// SOLID selected-blue fill with onSelected text (#210 — the tint+ring
/// treatment read too muted in the field; one prominent look for every
/// toggled-on state). Ink fills stay reserved for actions. 40 pt
/// segments (46 with container padding, §H) and the one motion rule
/// (§2): 0.15 s ease-out, selection haptic.
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
                        .foregroundStyle(selectedIndex == index ? Theme.onSelected : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            selectedIndex == index ? Theme.selected : .clear,
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                }
            }
        }
        .padding(3)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
        .animation(.easeOut(duration: 0.15), value: selectedIndex)
        .sensoryFeedback(.selection, trigger: selectedIndex)
    }
}
