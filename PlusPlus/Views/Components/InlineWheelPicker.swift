import SwiftUI

/// An always-visible horizontal "wheel" selector: the selected option sits
/// CENTERED with its neighbours peeking at the left/right edges (only where
/// one exists — the ends don't wrap). Swiping left/right OR tapping a peeking
/// edge option changes the selection; it stops at the ends.
///
/// Built on native scroll mechanics — `ScrollView(.horizontal)` +
/// `.scrollTargetBehavior(.viewAligned)` + `.scrollPosition(id:)` — rather than
/// a hand-rolled gesture, so the physics are the system's (snappy, inertial)
/// and it can NEVER overflow the viewport (it IS a scroll view). Replaces the
/// retired `SegmentedTabs` on the Find-or-create scope surface, whose
/// content-width mode could scroll its whole track off-screen.
///
/// Selection stays in the blue selection grammar: the centred cell wears the
/// solid `Theme.selected` pill; peeking cells dim to `Theme.textSecondary` and
/// shrink slightly via `.scrollTransition`, with the edges softened by a fade
/// mask so the peek reads as "there's more either way".
struct InlineWheelPicker: View {
    let options: [String]
    @Binding var selectedIndex: Int
    /// Per-segment leading SF Symbol; nil entries (or a nil array) are
    /// text-only. Count should match `options` when provided.
    var symbols: [String?]? = nil
    /// Per-segment accessibility identifiers (XCUITest hooks); nil falls back
    /// to no identifier.
    var identifiers: [String]? = nil
    /// Identifier on the scroll track itself, so a UI test can swipe the wheel
    /// to reach an off-centre (not-hittable) segment before tapping it.
    var scrollIdentifier: String? = nil

    /// The fraction of the track width the centred cell claims. The remainder
    /// splits into the two side margins, which is exactly how much of each
    /// neighbour peeks.
    private let centerFraction: CGFloat = 0.56
    private let spacing: CGFloat = 8
    private let cellHeight: CGFloat = 44

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The id of the cell currently aligned to centre — the single internal
    /// source of truth. Swiping updates it (scroll settle); tapping/external
    /// selection drives it, which scrolls the wheel.
    @State private var centeredID: Int?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let cellWidth = max(1, width * centerFraction)
            let sideMargin = max(0, (width - cellWidth) / 2)

            ScrollView(.horizontal) {
                HStack(spacing: spacing) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        cell(index: index, option: option, width: cellWidth)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            // Symmetric side margins let the first and last cell reach centre,
            // and turn the leading-aligned snap of `.viewAligned` into a
            // CENTRED snap.
            .contentMargins(.horizontal, sideMargin, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centeredID, anchor: .center)
            .mask(edgeFade)
            .accessibilityID(scrollIdentifier)
        }
        .frame(height: cellHeight)
        .sensoryFeedback(.selection, trigger: selectedIndex)
        .onAppear { centeredID = selectedIndex }
        .onChange(of: centeredID) { _, new in
            if let new, new != selectedIndex { selectedIndex = new }
        }
        .onChange(of: selectedIndex) { _, new in
            guard new != centeredID else { return }
            withAnimation(Theme.Anim.selection) { centeredID = new }
        }
    }

    private func cell(index: Int, option: String, width: CGFloat) -> some View {
        let selected = selectedIndex == index
        let flat = reduceMotion
        return Button {
            // Drive the internal id (animated) — the onChange syncs the binding.
            withAnimation(Theme.Anim.selection) { centeredID = index }
        } label: {
            HStack(spacing: 5) {
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
            .frame(width: width, height: cellHeight)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9).fill(Theme.selected)
                }
            }
        }
        .buttonStyle(.plain)
        .scrollTransition { content, phase in
            // Peeking (non-centred) cells shrink + dim; the centred cell is
            // identity. Under Reduce Motion keep it flat.
            content
                .opacity(phase.isIdentity || flat ? 1 : 0.5)
                .scaleEffect(phase.isIdentity || flat ? 1 : 0.92)
        }
        .accessibilityID(identifier(at: index))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.10),
                .init(color: .black, location: 0.90),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func symbol(at index: Int) -> String? {
        guard let symbols, symbols.indices.contains(index) else { return nil }
        return symbols[index]
    }

    private func identifier(at index: Int) -> String? {
        guard let identifiers, identifiers.indices.contains(index) else { return nil }
        return identifiers[index]
    }
}

private extension View {
    /// Apply an accessibility identifier only when one is provided.
    @ViewBuilder func accessibilityID(_ id: String?) -> some View {
        if let id { accessibilityIdentifier(id) } else { self }
    }
}
