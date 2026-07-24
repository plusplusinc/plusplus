import SwiftUI

/// A horizontal take on the native vertical picker wheel: a FIXED centred
/// selection band that the options wheel through — the band never moves, the
/// items scroll past it. The option under the band is the selection (white
/// text); the others are grey and curve away with a slight 3D cylinder tilt,
/// staying legible at the sides. Swipe or tap a side option to change it; it
/// stops at the ends (no wrap).
///
/// Built on native scroll mechanics — `ScrollView(.horizontal)` +
/// `.scrollTargetBehavior(.viewAligned)` + `.scrollPosition(id:)` — so the
/// physics are the system's and it can NEVER overflow the viewport (it IS a
/// scroll view). The cylinder depth is a per-frame `.visualEffect` keyed on each
/// cell's distance from the band centre, so it grades continuously as you drag
/// (like the real wheel), not in discrete steps. Replaces the retired
/// `SegmentedTabs` on the Find-or-create scope surface.
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

    /// The fraction of the track width the centred slot (and the band) claims.
    /// The remainder splits into the two side margins, which is how much of each
    /// neighbour shows — kept generous so the sides stay clearly readable.
    private let centerFraction: CGFloat = 0.42
    private let spacing: CGFloat = 6
    private let cellHeight: CGFloat = 44
    private let bandHeight: CGFloat = 40

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The id of the cell currently under the band — the single internal source
    /// of truth. Swiping updates it (scroll settle); tapping/external selection
    /// drives it, which scrolls the wheel.
    @State private var centeredID: Int?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let cellWidth = max(1, width * centerFraction)
            let sideMargin = max(0, (width - cellWidth) / 2)
            let allowMotion = !reduceMotion

            ScrollView(.horizontal) {
                HStack(spacing: spacing) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        cell(index: index, option: option,
                             cellWidth: cellWidth, trackWidth: width, allowMotion: allowMotion)
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
            // The fixed selection band the options wheel through (it never
            // moves). surfaceRaised on the surface = the native picker's subtle
            // lighter slab.
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.surfaceRaised)
                    .frame(width: cellWidth, height: bandHeight)
            }
            .accessibilityID(scrollIdentifier)
        }
        .frame(height: cellHeight)
        .sensoryFeedback(.selection, trigger: selectedIndex)
        .onAppear { centeredID = selectedIndex }
        .onChange(of: centeredID) { _, new in
            if let new, new != selectedIndex { selectedIndex = new }
        }
        .onChange(of: selectedIndex) { _, new in
            // Jump WITHOUT animation on an external selection change: an animated
            // multi-cell scroll would report every intermediate cell through
            // `.scrollPosition`, and each round-trips back into the bound value
            // (flashing the wrong selection mid-animation). A tap moves one
            // adjacent cell, so its own `withAnimation` has no intermediates.
            guard new != centeredID else { return }
            centeredID = new
        }
    }

    private func cell(index: Int, option: String,
                      cellWidth: CGFloat, trackWidth: CGFloat, allowMotion: Bool) -> some View {
        let selected = centeredID == index
        return Button {
            // Drive the internal id (animated) — the onChange syncs the binding.
            withAnimation(Theme.Anim.selection) { centeredID = index }
        } label: {
            HStack(spacing: 5) {
                if let symbol = symbol(at: index) {
                    Image(systemName: symbol)
                        .font(.system(.subheadline, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(option)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.system(.subheadline, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
            .frame(width: cellWidth, height: cellHeight)
        }
        .buttonStyle(.plain)
        // Continuous cylinder: grade depth/opacity by the cell's signed distance
        // from the band centre (in cell units), so it curves like the real wheel
        // as you drag — not a discrete on/off.
        .visualEffect { content, geo in
            let midX = geo.frame(in: .scrollView(axis: .horizontal)).midX
            let d = (midX - trackWidth / 2) / (cellWidth + spacing)
            let c = max(-2.5, min(2.5, d))
            return content
                .opacity(1 - min(abs(c) * 0.20, 0.55))
                .scaleEffect(1 - min(abs(c) * 0.05, 0.16))
                .rotation3DEffect(
                    .degrees(allowMotion ? Double(c) * -32 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.55
                )
        }
        .accessibilityID(identifier(at: index))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
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
