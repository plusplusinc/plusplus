import SwiftUI

/// The catalog scope control: a **flat** segmented control riding the
/// `.principal` navigation-bar row on both catalog roots, between the ++ key
/// and the kit switcher.
///
/// ⚠️ **The 3D is GONE (Dave, 2026-08-06, same day it shipped in build 193:
/// "let's kill the 3d for the segmented control").** The raised version wore
/// an opaque cap on a `Theme.border` plate, sliding and sinking like the keys
/// flanking it. On device it read CRAMPED and the containment was wrong: the
/// ++ key and the kit switcher are caps sitting directly on the bar, while
/// this sat in a well — a fourth shape neither neighbour has, so it read as a
/// key inside a box rather than as one of the three. Making it flat is what
/// `design-grammar.md` said in the first place.
///
/// **So both deviations that version carried are RETIRED, not narrowed.**
/// - "Flat controls (chips, toggles, segments, rows) stay flat" binds again,
///   and a raised cap goes back to meaning "this commits or navigates".
/// - The ONE selection look is whole again: tinted ground (`selectedTint`) +
///   ring (`selectedRing`) + `selectedInk` label. Elevation carries nothing.
///
/// **The anatomy is `SelectableChip`'s, scaled to a track.** A recessed track
/// spans the control (`Theme.surface` + `Theme.border` at `keyRadius`); the
/// selected scope wears the selection look on a pill inset inside it.
/// Selecting SLIDES that pill (`Theme.Anim.selection` — the selection-slides
/// law, which is unaffected by any of this). There is no press response and
/// deliberately so: a flat control's state flip IS its feedback.
///
/// ⚠️ **The inset is 3 pt and the pill's radius is `keyRadius - inset`.** Not
/// arbitrary — concentric corners have to be the outer radius minus the gap
/// between them, or the two curves visibly disagree. The raised version had
/// both at `keyRadius` about a point apart, which is the same fault the
/// sheet-corner experiment was reverted for (design-grammar, 2026-07-19).
///
/// ⚠️ **Not a `Picker(.segmented)`.** navigation.md's "do NOT hand-roll the
/// segmented control" law forbids faking iOS 26's interactive glass, which
/// belongs to tab bars and native segmented controls alone. This wears the
/// app's own chip grammar on purpose, which a `UISegmentedControl` cannot be
/// made to do — and which also drops that control's platform limit: a segment
/// takes a title OR an image, never both (DTS, forums 816517). That limit is
/// why the 2026-07-26 control was glyph-only and why the wheel stacked icon
/// over label to escape it. ⚠️ This control carries NEITHER inheritance: it is
/// one WORD per cell (build 194 — see `cell`, where stacking is what broke).
/// The whole icon-and-label question was an artifact of a platform limit that
/// stopped applying the moment the app drew the control itself.
///
/// ⚠️ **No layout-fed state writes.** The cell width is a pure
/// `GeometryReader` READ used inline, from a `.background` so it can neither
/// be stored nor influence the size it measures — a layout-driven write
/// anywhere in the `TabView` subtree is the documented iOS 26 search-morph
/// killer (navigation.md, nav-diag 4e).
///
/// ⚠️ **Known, not fixed: the pill is seated with `.offset(x:)`, which is not
/// layout-direction aware**, while the `HStack`'s cell order and the
/// `GeometryReader`'s `.topLeading` placement both are. Under RTL the pill
/// would seat from the trailing edge and then be pushed further trailing,
/// landing outside the track for any index > 0. Unreachable today (the app
/// ships no `.lproj` bundles, so only the RTL pseudolanguage gets there) and
/// the wheel and the raised version had the identical shape — named here so
/// it is not mistaken for handled the day a localization lands.
///
/// Accessibility: each scope is a labelled `Button` carrying `.isSelected`, so
/// VoiceOver reads "Exercises, selected, button" and Voice Control works by
/// name. Identifiers are unchanged across all three shapes this control has
/// worn (`findScope-<scope>-<instance>`), so the smoke suite carries over.
struct ScopeSegmentedControl: View {
    @Binding var scope: FindScope
    /// Which mounted instance this is ("browse" / "search") — suffixed onto
    /// every accessibility identifier. Browse and search each mount a control
    /// over the SAME scope state, and instances in inactive tabs are visible
    /// to XCUITest queries, so a shared identifier is a guaranteed
    /// multiple-match the moment both tabs have been built.
    let instanceKey: String

    /// ⚠️ Matches the flanking keys' CAP height, not their full height. A key
    /// is a 44 pt cap plus `RaisedKeyStyle`'s 4 pt of travel, and the cap is
    /// what the eye lines up. Being flat, this control has no travel of its
    /// own — so the MOUNT SITE adds that 4 pt back as bottom padding, exactly
    /// as it did for the wheel. Height and padding are one decision: change
    /// either and the row stops sharing a baseline.
    private let height: CGFloat = 44
    /// The gap between the track and the selected pill, on every side.
    private let inset: CGFloat = 3

    @State private var hapticTick = 0

    private var options: [FindScope] { FindScope.allCases }
    private var selectedIndex: Int { options.firstIndex(of: scope) ?? 0 }

    var body: some View {
        // ⚠️ The CELLS are the layout; track and selection are backgrounds
        // behind them. NOT a `GeometryReader` at the root: it fills what it is
        // offered and has no ideal size, so on the pass where the bar row's
        // width is still unknown it would collapse the control to a stub — and
        // on the search tab that pass IS the first activation. An `HStack` of
        // labelled cells has a real ideal width.
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                cell(index: index, option: option)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height)
        .background(alignment: .topLeading) {
            GeometryReader { proxy in
                // PURE read: used inline, never stored. See the header.
                selection(width: proxy.size.width / CGFloat(options.count))
            }
        }
        .background(track)
        // Chrome sharing a row with two keys can't grow without bound, and a
        // segmented control TRUNCATES rather than wrapping. ⚠️ The cap bounds
        // how far the labels push; `minimumScaleFactor` absorbs the rest, and
        // dropping the glyph gave each word the cell's full width AND full
        // height. What the cap can no longer do is hide a LAYOUT fault — the
        // build-194 overflow was the icon stack outgrowing a 44 pt control,
        // and a Dynamic Type ceiling would only have moved the size at which
        // it broke. The search field is NOT capped: its text is the user's own.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .sensoryFeedback(.selection, trigger: hapticTick)
    }

    /// The track the segments sit in. `surface` rather than the page, so the
    /// control reads as one object rather than three loose chips — which
    /// matters because the facet row directly below IS three loose chips, and
    /// the two rows have to stay tellable apart.
    ///
    /// ⚠️ **`borderStrong`, not `border`**, and it is the same number twice
    /// over: it is what `SelectableChip` and `FacetChip` stroke unselected
    /// (so this really is their anatomy rather than a lookalike), AND what
    /// both flanking keys stroke (so the bar row shares one edge weight).
    /// Drawn at `border` for its first cut, the track measured 1.38:1 against
    /// the light-mode page while the keys carried 1.82:1 — two crisp keys with
    /// a ghost between them, which is the "one family" read failing for the
    /// opposite reason the raised version failed.
    private var track: some View {
        RoundedRectangle(cornerRadius: Theme.keyRadius)
            .fill(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.keyRadius)
                    .strokeBorder(Theme.borderStrong)
            )
    }

    /// The selected scope's ground: the app's ONE selection look, on a pill
    /// inset inside the track. Radius is `keyRadius - inset` so it is properly
    /// concentric with the track's corners (see the header).
    private func selection(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Theme.keyRadius - inset)
            .fill(Theme.selectedTint)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.keyRadius - inset)
                    .strokeBorder(Theme.selectedRing)
            )
            .frame(width: max(width - inset * 2, 0), height: height - inset * 2)
            .offset(x: CGFloat(selectedIndex) * width + inset, y: inset)
            // `Theme.Anim.selection` already resolves near-instant under
            // Reduce Motion (the pill arrives instead of travelling).
            .animation(Theme.Anim.selection, value: selectedIndex)
            .allowsHitTesting(false)
    }

    private func cell(index: Int, option: FindScope) -> some View {
        let isSelected = index == selectedIndex
        return Button {
            guard option != scope else { return }
            scope = option
            hapticTick += 1
        } label: {
            // ⚠️ ONE LINE, no glyph — and the icons went for a CORRECTNESS
            // reason, not a taste one (Dave, build 194: "still pretty
            // fucked"). Stacking icon over label put two things in a 44 pt
            // control, and at his Dynamic Type size the stack grew taller
            // than the 38 pt selection pill: the pill's border drew straight
            // through "Routines" and the glyph crossed its top edge. Both
            // neighbours in this row are single-line (`LibrarySwitcherKey` is
            // one `.footnote` in a 44 pt frame, and it reflows fine at the
            // same size) — the scope control was the only thing stacking, so
            // it was the only thing that broke.
            //
            // The stack was always a WIDTH compromise inherited from the
            // wheel, which inherited it from the glyph-only segmented control
            // it replaced. Nothing needs it here: one word per cell reads
            // better, gets the full cell height AND width, and cannot
            // overflow its own pill.
            Text(option.label)
                // `.footnote`, matching the kit switcher exactly, so the row
                // reads at one size.
                .font(.system(.footnote, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(isSelected ? Theme.selectedInk : Theme.textSecondary)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        // ⚠️ `.plain`, and nothing else. A flat control's state flip is its
        // feedback (design-grammar) — no press offset, no latch, and so none
        // of the gesture-latch hazards the raised version had to defend
        // against.
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("findScope-\(option.rawValue)-\(instanceKey)")
    }
}
