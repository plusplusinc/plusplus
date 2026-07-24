import SwiftUI

/// Segmented control in the selection grammar: the active tab is a
/// SOLID selected-blue fill with onSelected text (#210 — the tint+ring
/// treatment read too muted in the field; one prominent look for every
/// toggled-on state). Ink fills stay reserved for actions. 44 pt
/// segments (meets the HIG touch-target floor). The pill slides on
/// `Theme.Anim.selection` (a snappy spring) with a selection haptic —
/// an ease-out's decelerating tail made the slide read muddy (§2).
///
/// Two width modes. The default divides the bar into EQUAL segments
/// (`maxWidth: .infinity`). `widthsByContent` sizes each segment to its
/// own content + padding instead — the HIG-legal non-uniform layout
/// (segments "usually" share a width, not always) — so a long label
/// ("Exercises") gets its room while short ones stay tight; the track
/// hugs the group and scrolls horizontally if it ever exceeds the width
/// (accessibility Dynamic Type). Optional per-segment `symbols` prepend an
/// SF Symbol (nil entries render text-only, e.g. an "All" segment), and the
/// sliding pill resizes as it moves between unequal segments for free.
struct SegmentedTabs: View {
    let options: [String]
    @Binding var selectedIndex: Int
    /// Per-segment leading SF Symbol; nil entries (or a nil array) are
    /// text-only. Count must match `options` when provided.
    var symbols: [String?]? = nil
    /// Per-segment accessibility identifiers (XCUITest hooks); nil falls
    /// back to no identifier, the historical behavior.
    var identifiers: [String]? = nil
    /// false (default) = equal-width segments; true = content-width.
    var widthsByContent = false
    /// The fill is ONE object that slides between segments (#216) —
    /// selection is a thing you move, not a pair of crossfades.
    @Namespace private var pillNamespace

    var body: some View {
        Group {
            if widthsByContent {
                // Content-width: the track hugs the segments; a horizontal
                // ScrollView catches overflow at large Dynamic Type rather
                // than clipping (the "reflow, don't cap" instinct, #164).
                ScrollView(.horizontal, showsIndicators: false) {
                    segments.fixedSize(horizontal: true, vertical: false)
                }
            } else {
                segments
            }
        }
        .animation(Theme.Anim.selection, value: selectedIndex)
        .sensoryFeedback(.selection, trigger: selectedIndex)
    }

    private var segments: some View {
        HStack(spacing: 3) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    selectedIndex = index
                } label: {
                    segmentLabel(index: index, option: option)
                }
                .accessibilityID(identifier(at: index))
                .accessibilityAddTraits(selectedIndex == index ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }

    // Safe accessors: a caller passing a shorter symbols/identifiers array
    // than `options` degrades to no-symbol / no-id rather than crashing.
    private func symbol(at index: Int) -> String? {
        guard let symbols, symbols.indices.contains(index) else { return nil }
        return symbols[index]
    }

    private func identifier(at index: Int) -> String? {
        guard let identifiers, identifiers.indices.contains(index) else { return nil }
        return identifiers[index]
    }

    private func segmentLabel(index: Int, option: String) -> some View {
        let selected = selectedIndex == index
        return HStack(spacing: 5) {
            if let symbol = symbol(at: index) {
                Image(systemName: symbol)
                    .font(.system(.footnote, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(option)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.system(.footnote, weight: .semibold))
        .foregroundStyle(selected ? Theme.onSelected : Theme.textSecondary)
        // Equal mode fills the segment; content mode pads to hug its label.
        .frame(maxWidth: widthsByContent ? nil : .infinity)
        .padding(.horizontal, widthsByContent ? 14 : 0)
        .frame(height: 44)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Theme.selected)
                    .matchedGeometryEffect(id: "pill", in: pillNamespace)
            }
        }
    }
}

private extension View {
    /// Apply an accessibility identifier only when one is provided, so
    /// callers that pass none keep their historical (identifier-free) tree.
    @ViewBuilder func accessibilityID(_ id: String?) -> some View {
        if let id { accessibilityIdentifier(id) } else { self }
    }
}
