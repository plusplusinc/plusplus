import SwiftUI

/// Segmented control in the v4 selection grammar (§D): the active tab
/// speaks blue — selectedTint fill, selected text, 1 pt selectedRing —
/// because choosing a tab changes what you're looking at; ink fills are
/// reserved for actions. 40 pt segments (46 with container padding, §H)
/// and the one motion rule (§2): 0.15 s ease-out, selection haptic.
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
                        .foregroundStyle(selectedIndex == index ? Theme.selected : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            selectedIndex == index ? Theme.selectedTint : .clear,
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(selectedIndex == index ? Theme.selectedRing : .clear, lineWidth: 1)
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
