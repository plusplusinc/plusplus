import SwiftUI

/// A horizontal take on the native vertical picker wheel: a FIXED selection band
/// the options wheel through — the band never moves, the items scroll past it.
/// The band is pinned LEFT (its leading edge on the content column) and sized to
/// the WIDEST option plus even padding. The option under the band is the
/// selection (white text); the others are grey and curve away with a soft 3D
/// cylinder tilt. Faint chevrons inside the band point to options off either
/// side (the band is at the edge, so nothing peeks left); tapping a chevron
/// steps that way. Change it by dragging, tapping an option, or tapping a
/// chevron; it stops at the ends (no wrap).
///
/// Built on native scroll mechanics — `ScrollView(.horizontal)` +
/// `.scrollTargetBehavior(.viewAligned)` + `.scrollPosition(id:)` — so the
/// physics are the system's and it can NEVER overflow the viewport. The cylinder
/// depth is a per-frame `.visualEffect` keyed on each cell's distance from the
/// band centre, so it grades continuously as you drag. Replaces the retired
/// `SegmentedTabs` on the Find-or-create scope surface.
///
/// Accessibility: each option is a labelled Button carrying the `.isSelected`
/// trait (the segmented-control model — VoiceOver reads "Exercises, selected,
/// button"; Voice Control can say the name; the option's 44 pt row is the
/// target). The chevrons are a supplementary visual affordance and are hidden
/// from assistive tech. VoiceOver's reveal-scroll is prevented from changing the
/// selection — only a tap or drag does.
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

    /// Band's leading edge — the content column, so it lines up with the field
    /// and rows above/below it.
    private let leadingInset: CGFloat = 16
    /// Even space from the band edge to the chevron / content.
    private let edgePadding: CGFloat = 10
    /// Space between the option label and a chevron.
    private let labelGap: CGFloat = 12
    /// The chevron glyph's nominal width, reserved on each side of the label.
    private let chevronWidth: CGFloat = 9
    private let spacing: CGFloat = 6
    private let cellHeight: CGFloat = 44
    private let bandHeight: CGFloat = 40
    private let tiltDegrees: Double = 18

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn

    /// The id of the cell currently under the band — mirrors the scroll for the
    /// mechanics. `selectedIndex` is the source of truth for the SELECTION.
    @State private var centeredID: Int?
    /// The widest option's intrinsic width; the band sizes to it.
    @State private var maxLabelWidth: CGFloat = 0
    /// Chevrons fade out while the wheel is in motion.
    @State private var isScrolling = false

    private var last: Int { options.count - 1 }
    /// Reserved on EACH side of the label: edge padding + chevron + gap.
    private var sideReserve: CGFloat { edgePadding + chevronWidth + labelGap }
    private func bandWidth() -> CGFloat { maxLabelWidth + 2 * sideReserve }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let cellWidth = max(1, bandWidth())
            let trailingInset = max(0, width - cellWidth - leadingInset)
            let bandCenter = leadingInset + cellWidth / 2

            ScrollView(.horizontal) {
                HStack(spacing: spacing) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        cell(index: index, option: option, cellWidth: cellWidth, bandCenter: bandCenter)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .contentMargins(.leading, leadingInset, for: .scrollContent)
            .contentMargins(.trailing, trailingInset, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centeredID, anchor: UnitPoint(x: bandCenter / max(width, 1), y: 0.5))
            .onScrollPhaseChange { _, phase in isScrolling = phase != .idle }
            .accessibilityID(scrollIdentifier)
            // The fixed selection band (behind the cells), pinned LEFT.
            .background(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.surfaceRaised)
                    .frame(width: cellWidth, height: bandHeight)
                    .padding(.leading, leadingInset)
            }
            // Chevrons on top of the cells, inside the band.
            .overlay(alignment: .leading) { chevrons(cellWidth: cellWidth) }
        }
        .frame(height: cellHeight)
        .background(alignment: .topLeading) { widthProbe }
        .sensoryFeedback(.selection, trigger: selectedIndex)
        .onAppear { centeredID = selectedIndex }
        .onChange(of: centeredID) { _, new in
            // A drag settling on a new cell selects it — but NOT VoiceOver's
            // reveal-scroll, which would change the selection just by navigating.
            guard !voiceOverOn, let new, new != selectedIndex else { return }
            selectedIndex = new
        }
        .onChange(of: selectedIndex) { old, new in
            guard new != centeredID else { return }
            // A one-step change (tap a neighbour / a chevron) slides; a multi-step
            // external jump goes straight there, so the scroll can't report the
            // cells it passes and flash the wrong selection.
            if abs(new - old) == 1 {
                withAnimation(Theme.Anim.selection) { centeredID = new }
            } else {
                centeredID = new
            }
        }
    }

    // MARK: Cells

    private func cell(index: Int, option: String, cellWidth: CGFloat, bandCenter: CGFloat) -> some View {
        // Track the scroll live for the visual (so white follows a drag), but
        // under VoiceOver pin it to the real selection (reveal-scroll must not
        // move the highlight).
        let visualSelected = voiceOverOn ? (selectedIndex == index) : ((centeredID ?? selectedIndex) == index)
        return Button {
            selectedIndex = index   // onChange scrolls the wheel to it
        } label: {
            label(index: index, option: option, selected: visualSelected)
                .frame(width: cellWidth, height: cellHeight)
        }
        .buttonStyle(.plain)
        .visualEffect { content, geo in
            let midX = geo.frame(in: .scrollView(axis: .horizontal)).midX
            let d = (midX - bandCenter) / (cellWidth + spacing)
            let c = max(-2.5, min(2.5, d))
            return content
                .opacity(1 - min(abs(c) * 0.18, 0.5))
                .scaleEffect(1 - min(abs(c) * 0.045, 0.14))
                .rotation3DEffect(
                    .degrees(reduceMotion ? 0 : Double(c) * -tiltDegrees),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.72
                )
        }
        .accessibilityLabel(option)
        .accessibilityAddTraits(visualSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityID(identifier(at: index))
    }

    @ViewBuilder
    private func label(index: Int, option: String, selected: Bool) -> some View {
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
    }

    // MARK: Chevrons

    private func chevrons(cellWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            chevron(.backward)
            Spacer(minLength: 0)
            chevron(.forward)
        }
        .padding(.horizontal, edgePadding)
        .frame(width: cellWidth, height: cellHeight)
        .padding(.leading, leadingInset)
        // A supplementary visual affordance — assistive tech uses the option
        // buttons, which are directly selectable.
        .accessibilityHidden(true)
    }

    private enum Dir { case backward, forward }

    private func chevron(_ dir: Dir) -> some View {
        let show = dir == .backward ? selectedIndex > 0 : selectedIndex < last
        return Button {
            step(dir == .backward ? -1 : 1)
        } label: {
            Image(systemName: dir == .backward ? "chevron.left" : "chevron.right")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(Theme.textFaint)
                // Hit zone extends into the reserved gap (never over the label),
                // full height for a comfortable target.
                .frame(width: chevronWidth + labelGap, height: cellHeight,
                       alignment: dir == .backward ? .leading : .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(show && !isScrolling ? 0.55 : 0)
        .allowsHitTesting(show && !isScrolling)
    }

    private func step(_ delta: Int) {
        let target = min(max(selectedIndex + delta, 0), last)
        if target != selectedIndex { selectedIndex = target }
    }

    // MARK: Width measurement

    /// A hidden stack of every option at its widest (semibold) weight; the ZStack
    /// sizes to the widest, which we read into `maxLabelWidth`.
    private var widthProbe: some View {
        ZStack {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                label(index: index, option: option, selected: true)
            }
        }
        .fixedSize()
        .hidden()
        .background(GeometryReader { g in
            Color.clear.preference(key: MaxLabelWidthKey.self, value: g.size.width)
        })
        .onPreferenceChange(MaxLabelWidthKey.self) { maxLabelWidth = $0 }
        .accessibilityHidden(true)
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

private struct MaxLabelWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    /// Apply an accessibility identifier only when one is provided.
    @ViewBuilder func accessibilityID(_ id: String?) -> some View {
        if let id { accessibilityIdentifier(id) } else { self }
    }
}
