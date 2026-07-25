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
/// `SegmentedTabs`. Restored 2026-07-25 as the scope picker inside the
/// TabView's bottom accessory.
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
    /// Inline placement: the accessory shares the tab bar's row, so the wheel
    /// loses its content-column inset and its rows get shorter. Everything else
    /// — the band, the peek, the chevrons, the tilt — is unchanged, so it reads
    /// as the same control in a tighter space rather than a second design.
    var compact: Bool = false

    /// Band's leading edge — the content column, so it lines up with the field
    /// and rows above/below it.
    private var leadingInset: CGFloat { compact ? 0 : 16 }
    /// Even space from the band edge to the chevron / content.
    private let edgePadding: CGFloat = 10
    /// Space between the option label and a chevron.
    private let labelGap: CGFloat = 12
    /// The chevron glyph's nominal width, reserved on each side of the label.
    private let chevronWidth: CGFloat = 9
    private let spacing: CGFloat = 6
    private var cellHeight: CGFloat { compact ? 34 : 44 }
    private var bandHeight: CGFloat { compact ? 30 : 40 }
    private let tiltDegrees: Double = 18

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn

    /// The id of the cell currently under the band — mirrors the scroll for the
    /// mechanics. `selectedIndex` is the source of truth for the SELECTION.
    @State private var centeredID: Int?
    /// The widest option's intrinsic width; the band sizes to it.
    /// Chevrons fade out while the user is DRAGGING the wheel (options wheel
    /// through the band); a tap-driven programmatic scroll does NOT count, so a
    /// chevron that stays visible across a tap doesn't flicker out and back.
    @State private var isDragging = false

    private var last: Int { options.count - 1 }
    /// Reserved on EACH side of the label: edge padding + chevron + gap.
    private var sideReserve: CGFloat { edgePadding + chevronWidth + labelGap }
    private func bandWidth() -> CGFloat { maxLabelWidth + 2 * sideReserve }

    /// The widest option label, from FONT METRICS rather than a layout probe.
    ///
    /// What this replaces: a hidden `ZStack` of every label behind a
    /// `GeometryReader` + `PreferenceKey` + `onPreferenceChange`, i.e. a state
    /// write during layout. That is the documented iOS 26 trigger for
    /// `Tab(role: .search)`'s morph failing on first activation (nav-diag 4e) —
    /// and this control now lives in the TAB BAR'S OWN ACCESSORY, which is the
    /// worst possible place to put one. Measuring is synchronous, writes
    /// nothing, and the labels here are three fixed words.
    private var maxLabelWidth: CGFloat {
        let base = UIFont.preferredFont(forTextStyle: .subheadline)
        let semibold = UIFont(
            descriptor: base.fontDescriptor.withSymbolicTraits(.traitBold) ?? base.fontDescriptor,
            size: base.pointSize
        )
        return options.enumerated().reduce(CGFloat(0)) { widest, pair in
            var width = (pair.element as NSString).size(withAttributes: [.font: semibold]).width
            // The glyph is roughly square at the cap height, plus the HStack's
            // 5 pt spacing (mirrors `label(index:option:selected:)`).
            if symbol(at: pair.offset) != nil { width += semibold.pointSize * 1.2 + 5 }
            return max(widest, ceil(width))
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // Clamp to the viewport so the intrinsic band never overflows at
            // accessibility text sizes; the label's minimumScaleFactor then
            // absorbs any shortfall rather than the wheel running off-screen.
            let cellWidth = max(1, min(bandWidth(), width - leadingInset - 8))
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
            // Only a finger drag (interacting / its coast) fades the chevrons —
            // NOT `.animating` (a tap's programmatic scroll), so tapping between
            // two values that both keep a chevron leaves it steady.
            .onScrollPhaseChange { _, phase in
                isDragging = phase == .interacting || phase == .decelerating
            }
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
        .visualEffect { [flat = reduceMotion] content, geo in
            let midX = geo.frame(in: .scrollView(axis: .horizontal)).midX
            let d = (midX - bandCenter) / (cellWidth + spacing)
            let c = max(-2.5, min(2.5, d))
            // Gentler fade (floor ~0.75) so peeking options stay legible — they
            // are tap targets. Under Reduce Motion the whole scroll-linked depth
            // (opacity + scale + rotation), not just the rotation, is flattened.
            return content
                .opacity(flat ? 1 : 1 - min(abs(c) * 0.10, 0.25))
                .scaleEffect(flat ? 1 : 1 - min(abs(c) * 0.045, 0.14))
                .rotation3DEffect(
                    .degrees(flat ? 0 : Double(c) * -tiltDegrees),
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
        let visible = show && !isDragging
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
        // Animate on the visibility state itself, so a chevron only fades when
        // it actually appears/disappears (or on a drag) — never mid-tap when it
        // stays visible on both sides.
        .opacity(visible ? 0.55 : 0)
        .allowsHitTesting(visible)
        .animation(Theme.Anim.standard, value: visible)
    }

    private func step(_ delta: Int) {
        let target = min(max(selectedIndex + delta, 0), last)
        if target != selectedIndex { selectedIndex = target }
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
