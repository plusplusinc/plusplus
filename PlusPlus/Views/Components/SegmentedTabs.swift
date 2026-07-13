import SwiftUI

/// Segmented control in the selection grammar: the active tab is a
/// SOLID selected-blue fill with onSelected text (#210 — the tint+ring
/// treatment read too muted in the field; one prominent look for every
/// toggled-on state). Ink fills stay reserved for actions. 44 pt
/// segments (meets the HIG touch-target floor). The pill slides on
/// `Theme.Anim.selection` (a snappy spring) with a selection haptic —
/// an ease-out's decelerating tail made the slide read muddy (§2).
struct SegmentedTabs: View {
    let options: [String]
    @Binding var selectedIndex: Int
    /// The fill is ONE object that slides between segments (#216) —
    /// selection is a thing you move, not a pair of crossfades.
    @Namespace private var pillNamespace

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    selectedIndex = index
                } label: {
                    Text(option)
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(selectedIndex == index ? Theme.onSelected : Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background {
                            if selectedIndex == index {
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(Theme.selected)
                                    .matchedGeometryEffect(id: "pill", in: pillNamespace)
                            }
                        }
                }
                .accessibilityAddTraits(selectedIndex == index ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
        .animation(Theme.Anim.selection, value: selectedIndex)
        .sensoryFeedback(.selection, trigger: selectedIndex)
    }
}
