import SwiftUI

/// The catalog scope control: a horizontal take on the native vertical picker
/// wheel — a FIXED selection band the scopes wheel through. The band never
/// moves; the items scroll past it. Revived from `InlineWheelPicker` (#447,
/// retired with `FindOrCreateView` when the search surface went native) for
/// the three-tab bar (2026-08-05): it escapes the `UISegmentedControl`
/// platform limit that forced `ScopeSegmentedControl` to glyphs only — a
/// segment takes a title OR an image, never both (DTS, forums 816517) — by
/// stacking the icon OVER the label, which also halves each item's width so
/// the band plus both neighbours fit the principal row beside the ++ key and
/// the kit switcher.
///
/// Two deliberate changes from the #447 original, and one law:
/// - **Selection grammar** (2026-07-28/31): the band wears the ONE selection
///   look — `selectedTint` ground + `selectedRing` + `selectedInk` content —
///   in place of the era's white/grey. Chevrons stay quiet faint ink; the
///   cells stay FLAT (chips/segments never take the raised-key treatment).
/// - **Width from `UIFont` metrics, not a probe.** The original measured its
///   widest label with a hidden `PreferenceKey` probe — a state write fed by
///   layout, which inside the TabView subtree is the documented iOS 26
///   search-morph killer (navigation.md; nav-diag 4e). The measurement is now
///   a pure per-render `UIFont` computation, the sanctioned pattern.
/// - ⚠️ `.scrollPosition(id:)` + `.onScrollPhaseChange` still mirror the
///   SCROLL into state. That is scroll-driven, not layout-driven — a
///   different write class from the banned probes — but it is untested
///   against the first-activation morph and is the #1 device check for this
///   control (docs/DEVICE-PASS.md). If the morph objects, the fallback seat
///   is the pinned facet-row header in content (#447's own lineage), not a
///   revert to glyphs.
///
/// Built on native scroll mechanics — `ScrollView(.horizontal)` +
/// `.scrollTargetBehavior(.viewAligned)` + `.scrollPosition(id:)` — so the
/// physics are the system's and it can never overflow the viewport. The band
/// is pinned LEFT (the row supplies the gaps) and sized intrinsically to the
/// widest label; the cylinder depth is a per-frame `.visualEffect` keyed on
/// each cell's distance from the band centre, a pure layout READ.
///
/// Accessibility (the #447 model, unchanged): each option is a labelled
/// `Button` carrying `.isSelected` — VoiceOver reads "Exercises, selected,
/// button", Voice Control works by name, the 44 pt cell is the target. The
/// chevrons are supplementary and hidden from assistive tech. VoiceOver's
/// reveal-scroll is gated out of the selection sync: navigating options must
/// not change the scope, only a tap or drag does.
struct ScopeWheel: View {
    @Binding var scope: FindScope

    /// Even space from the band edge to a chevron.
    private let edgePadding: CGFloat = 6
    /// The chevron glyph's nominal width, reserved on each side of the label.
    private let chevronWidth: CGFloat = 6
    /// Space between a chevron and the label column.
    private let labelGap: CGFloat = 2
    private let spacing: CGFloat = 6
    private let cellHeight: CGFloat = 44
    private let bandHeight: CGFloat = 40
    private let tiltDegrees: Double = 18

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The id of the cell currently under the band — mirrors the scroll for
    /// the mechanics. `scope` is the source of truth for the SELECTION.
    @State private var centeredID: Int?
    /// Chevrons fade out while the wheel is in motion.
    @State private var isScrolling = false

    private var options: [FindScope] { FindScope.allCases }
    private var selectedIndex: Int { options.firstIndex(of: scope) ?? 0 }
    private var last: Int { options.count - 1 }
    /// Reserved on EACH side of the label column: edge pad + chevron + gap.
    private var sideReserve: CGFloat { edgePadding + chevronWidth + labelGap }

    /// The widest label at its selected (semibold) weight, from `UIFont`
    /// metrics — never a layout probe (see the header). Re-derived per render,
    /// so a Dynamic Type change lands on the next pass; measured at the same
    /// capped category the view renders at, so band and text can't disagree.
    private var maxLabelWidth: CGFloat {
        let style = UIFont.TextStyle.caption2
        let capped = min(dynamicTypeSize, .accessibility1)
        let traits = UITraitCollection(preferredContentSizeCategory: capped.contentSizeCategory)
        let base = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits)
        let font: UIFont = base.fontDescriptor.withSymbolicTraits(.traitBold).map {
            UIFont(descriptor: $0, size: 0)
        } ?? base
        let widest = options
            .map { ceil(($0.label as NSString).size(withAttributes: [.font: font]).width) }
            .max() ?? 0
        // The icon column is narrower than any label here, but keep the floor
        // honest in case a future scope's name shrinks below its glyph.
        return max(widest, 24)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // Clamp to the viewport so the intrinsic band never overflows at
            // accessibility sizes; `minimumScaleFactor` absorbs any shortfall
            // rather than the wheel running off-screen.
            let cellWidth = max(1, min(maxLabelWidth + 2 * sideReserve, width - 8))
            let bandCenter = cellWidth / 2

            ScrollView(.horizontal) {
                HStack(spacing: spacing) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        cell(index: index, option: option, cellWidth: cellWidth, bandCenter: bandCenter)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            // The band sits at the wheel's own leading edge — the principal
            // row supplies the content-column gaps — and the trailing margin
            // is what lets the last scope reach the band.
            .contentMargins(.trailing, max(0, width - cellWidth), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centeredID, anchor: UnitPoint(x: bandCenter / max(width, 1), y: 0.5))
            .onScrollPhaseChange { _, phase in isScrolling = phase != .idle }
            .accessibilityIdentifier("scopeWheel")
            // The fixed selection band (behind the cells), pinned LEFT,
            // wearing the selection look every selected control shares.
            .background(alignment: .leading) {
                RoundedRectangle(cornerRadius: Theme.keyRadius)
                    .fill(Theme.selectedTint)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.keyRadius)
                            .strokeBorder(Theme.selectedRing, lineWidth: 1)
                    )
                    .frame(width: cellWidth, height: bandHeight)
            }
            // Chevrons on top of the cells, inside the band's edges.
            .overlay(alignment: .leading) { chevrons(cellWidth: cellWidth) }
        }
        .frame(height: cellHeight)
        // Chrome shared with the bar's keys can't grow without bound — the
        // same cap the segmented control carried.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .sensoryFeedback(.selection, trigger: scope)
        .onAppear { centeredID = selectedIndex }
        .onChange(of: centeredID) { _, new in
            // A drag settling on a new cell selects it — but NOT VoiceOver's
            // reveal-scroll, which would change the scope just by navigating.
            guard !voiceOverOn, let new, options.indices.contains(new), new != selectedIndex else { return }
            scope = options[new]
        }
        .onChange(of: scope) { old, new in
            let oldIndex = options.firstIndex(of: old) ?? 0
            let newIndex = options.firstIndex(of: new) ?? 0
            guard newIndex != centeredID else { return }
            // A one-step change (tap a neighbour / a chevron) slides; a
            // multi-step external jump goes straight there, so the scroll
            // can't report the cells it passes and flash the wrong scope.
            if abs(newIndex - oldIndex) == 1 {
                withAnimation(Theme.Anim.selection) { centeredID = newIndex }
            } else {
                centeredID = newIndex
            }
        }
    }

    // MARK: Cells

    private func cell(index: Int, option: FindScope, cellWidth: CGFloat, bandCenter: CGFloat) -> some View {
        // Track the scroll live for the visual (so the selected look follows
        // a drag), but under VoiceOver pin it to the real selection.
        let visualSelected = voiceOverOn ? (selectedIndex == index) : ((centeredID ?? selectedIndex) == index)
        return Button {
            scope = option   // onChange scrolls the wheel to it
        } label: {
            // Icon OVER label — the stacked layout that halves the width the
            // #447 side-by-side cell needed, and what lets words survive the
            // principal row at all.
            VStack(spacing: 2) {
                Image(systemName: option.symbolName)
                    .font(.system(.footnote, weight: .semibold))
                    .accessibilityHidden(true)
                Text(option.label)
                    .font(.system(.caption2, weight: visualSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(visualSelected ? Theme.selectedInk : Theme.textSecondary)
            .frame(width: cellWidth, height: cellHeight)
        }
        .buttonStyle(.plain)
        // Continuous cylinder: depth graded by the cell's signed distance from
        // the band centre — a pure layout READ (`.visualEffect` never writes
        // state), which is what keeps it legal in the TabView subtree.
        .visualEffect { [flat = reduceMotion] content, geo in
            let midX = geo.frame(in: .scrollView(axis: .horizontal)).midX
            let d = (midX - bandCenter) / (cellWidth + spacing)
            let c = max(-2.5, min(2.5, d))
            // Gentle fade floor so peeking options stay legible — they are
            // tap targets. Under Reduce Motion the whole scroll-linked depth
            // is flattened, not just the rotation.
            return content
                .opacity(flat ? 1 : 1 - min(abs(c) * 0.10, 0.25))
                .scaleEffect(flat ? 1 : 1 - min(abs(c) * 0.045, 0.14))
                .rotation3DEffect(
                    .degrees(flat ? 0 : Double(c) * -tiltDegrees),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.72
                )
        }
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(visualSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("findScope-\(option.rawValue)")
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
                .font(.system(.caption2, weight: .semibold))
                .foregroundStyle(Theme.textFaint)
                // Hit zone extends into the reserved gap (never over the
                // label), full height for a comfortable target.
                .frame(width: chevronWidth + labelGap + edgePadding, height: cellHeight,
                       alignment: dir == .backward ? .leading : .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(show && !isScrolling ? 0.55 : 0)
        .allowsHitTesting(show && !isScrolling)
    }

    private func step(_ delta: Int) {
        let target = min(max(selectedIndex + delta, 0), last)
        if target != selectedIndex { scope = options[target] }
    }
}

private extension DynamicTypeSize {
    /// The UIKit category this SwiftUI size measures as — for `UIFont`
    /// metrics that must agree with what the capped view actually renders.
    var contentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}
