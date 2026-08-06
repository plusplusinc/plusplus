import SwiftUI

/// The catalog scope control: a segmented control the app draws itself, in the
/// **raised-key family** (Dave, 2026-08-06: "replace our custom horizontal
/// wheel with a custom segmented control instead. Make it match the design of
/// the 3d buttons somehow, so it goes nicely between the ++ and the kit
/// switcher"). It replaces `ScopeWheel` (2026-08-05, one build).
///
/// **The anatomy is `RaisedKeyStyle`'s, scaled to a track.** A recessed well
/// spans the control; the SELECTED scope wears an opaque cap sitting proud of
/// it, with the well's own `travel` showing beneath the cap as the plate strip
/// — the same read as the ++ key and the kit switcher it sits between, which
/// is the point. Selecting slides the cap (`Theme.Anim.selection`, the
/// selection-slides law); pressing the cap sinks it onto the plate
/// (`Theme.Anim.press`), exactly as every other key in the app does.
///
/// ⚠️ **This deviates from two standing laws, both deliberately, and both are
/// Dave's call rather than mine.**
/// - `design-grammar.md` says flat controls — "chips, toggles, segments, rows"
///   — stay flat, and that a raised cap is reserved for buttons that commit or
///   navigate. A scope segment does neither. The deviation is the whole ask:
///   the control has to belong to the row it sits in, and that row is two
///   raised keys.
/// - The ONE selection look is a tinted ground + ring + `selectedInk` label.
///   Here ELEVATION carries selection and the ground is the key's own opaque
///   cap, so only the `selectedInk` half survives. Selection is still stated
///   twice (raised, and blue) — it is the GROUND that changes voice.
///
/// ⚠️ **Not a `Picker(.segmented)`, and the reason inverted.** navigation.md's
/// "do NOT hand-roll the segmented control" law says iOS 26's interactive
/// glass belongs to tab bars and segmented controls alone, so an app-drawn one
/// cannot look native. True — and irrelevant now, because this one is not
/// trying to look native. It is trying to look like the app's own keys, which
/// a `UISegmentedControl` cannot be made to do. The law stands for anything
/// attempting the native LOOK; it does not bind a control wearing app chrome
/// on purpose. Wearing app chrome also drops the platform limit that shaped
/// every earlier version: a `UISegmentedControl` segment takes a title OR an
/// image, never both (DTS, forums 816517), which is why the 2026-07-26
/// control was glyph-only and why the wheel had to stack icon over label to
/// escape it. A view the app draws has no such rule; the stack here is a
/// WIDTH choice, kept because it is the proven fit for the principal row.
///
/// ⚠️ **No layout-fed state writes.** The cell width is a pure
/// `GeometryReader` READ used inline, from a `.background` so it cannot
/// influence the size it measures — never written to `@State` — because a
/// layout-driven write anywhere in the `TabView` subtree is the documented
/// iOS 26 search-morph killer (navigation.md, nav-diag 4e). The press latch is
/// gesture-driven, which is a different write class and is fine.
///
/// ⚠️ **The slide is app-authored animation inside a bar item**, which is the
/// one thing build 138 saw fail (a `matchedGeometryEffect` pill refused to
/// travel inside `tabViewBottomAccessory`). Two reasons to expect better here:
/// the accessory is a system-owned CONTAINER and the `.principal` item is a
/// title view the app fills, and this animates a plain `.offset` on a value
/// rather than a matched-geometry pairing across identities. Still the #1
/// device check for this control — if the cap teleports instead of sliding,
/// drop the animation rather than the control.
///
/// Accessibility: each scope is a labelled `Button` carrying `.isSelected`, so
/// VoiceOver reads "Exercises, selected, button" and Voice Control works by
/// name. The identifiers are unchanged from the wheel
/// (`findScope-<scope>-<instance>`), so the smoke suite's cell taps carry over.
struct ScopeSegmentedControl: View {
    @Binding var scope: FindScope
    /// Which mounted instance this is ("browse" / "search") — suffixed onto
    /// every accessibility identifier. Browse and search each mount a control
    /// over the SAME scope state, and instances in inactive tabs are visible
    /// to XCUITest queries, so a shared identifier is a guaranteed
    /// multiple-match the moment both tabs have been built.
    let instanceKey: String

    /// The plate strip under the cap — `RaisedKeyStyle`'s standard 4 pt, so
    /// this control's underside matches the keys flanking it exactly.
    private let travel: CGFloat = 4
    private let capHeight: CGFloat = 40

    /// Which cell the finger is on, for the cap's sink. Gesture-driven state,
    /// not layout-driven — see the header.
    @GestureState private var pressedIndex: Int?
    @State private var hapticTick = 0

    private var options: [FindScope] { FindScope.allCases }
    private var selectedIndex: Int { options.firstIndex(of: scope) ?? 0 }

    /// The cap sinks only when the finger is on the ALREADY-selected cell — a
    /// re-press of a raised key. Pressing a different cell slides the cap
    /// over, and the slide is that gesture's feedback.
    private var isSinking: Bool { pressedIndex == selectedIndex }

    var body: some View {
        // ⚠️ The CELLS are the layout, and the well and cap are backgrounds
        // behind them. Not a `GeometryReader` at the root, which was the first
        // shape and is wrong here: a `GeometryReader` fills what it is offered
        // and has no ideal size of its own, so on the pass where the bar row's
        // width is still unknown it proposes unbounded, `maxWidth: .infinity`
        // falls back to that ideal, and the control collapses to a stub — and
        // on the search tab that pass IS the first activation. An `HStack` of
        // labelled cells has a real ideal width, so the same pass renders a
        // sensible row. Measuring from `.background` also means the reader can
        // never influence the size it is reading.
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                cell(index: index, option: option)
                    .frame(maxWidth: .infinity)
                    .frame(height: capHeight)
            }
        }
        // The extra `travel` is the plate strip the well shows beneath the cap
        // — the same 4 pt `RaisedKeyStyle` reserves, so this control's
        // underside matches the keys flanking it without the mount site
        // padding anything.
        .frame(height: capHeight + travel, alignment: .top)
        .background(alignment: .topLeading) {
            GeometryReader { proxy in
                // PURE read: used inline, never stored. See the header.
                cap(width: proxy.size.width / CGFloat(options.count))
            }
        }
        .background(well)
        // Chrome sharing a row with two keys can't grow without bound, and a
        // segmented control TRUNCATES rather than wrapping — at accessibility
        // sizes three uncapped labels become three ellipses and the control
        // stops naming anything. The search field is NOT capped: its text is
        // the user's own.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .sensoryFeedback(.selection, trigger: hapticTick)
    }

    /// The recessed track the cap sits proud of. `surface` rather than the
    /// page, so an unselected segment reads as BELOW the row rather than level
    /// with it; the border is the same one a key's plate wears.
    private var well: some View {
        RoundedRectangle(cornerRadius: Theme.keyRadius)
            .fill(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.keyRadius)
                    .strokeBorder(Theme.border)
            )
    }

    /// The raised cap over the selected scope — `AppMenuKey`'s exact anatomy
    /// (opaque `background` fill, `borderStrong` stroke, `keyRadius`), so the
    /// three controls in this row read as one family.
    private func cap(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Theme.keyRadius)
            .fill(Theme.background)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.keyRadius)
                    .strokeBorder(Theme.borderStrong)
            )
            .frame(width: width, height: capHeight)
            .offset(x: CGFloat(selectedIndex) * width, y: isSinking ? travel : 0)
            // Two animations, two meanings, two tokens: the cap SLIDES between
            // scopes and SINKS under a finger. `Theme.Anim.selection` already
            // resolves near-instant under Reduce Motion (the cap arrives
            // instead of travelling), and `press` is deliberately unaffected —
            // a 4 pt depression is not vestibular motion.
            .animation(Theme.Anim.selection, value: selectedIndex)
            .animation(Theme.Anim.press, value: isSinking)
            .allowsHitTesting(false)
    }

    private func cell(index: Int, option: FindScope) -> some View {
        let isSelected = index == selectedIndex
        return Button {
            guard option != scope else { return }
            scope = option
            hapticTick += 1
        } label: {
            // Icon OVER label: a width choice, not a platform limit (header).
            // Stacked is what fits three scopes into the principal row beside
            // the ++ key and a variable-width kit switcher.
            VStack(spacing: 2) {
                Image(systemName: option.symbolName)
                    .font(.system(.footnote, weight: .semibold))
                    .accessibilityHidden(true)
                Text(option.label)
                    .font(.system(.caption2, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            // The blue half of the selection look survives; the GROUND is the
            // key's (header). An unselected label sits quiet on the well.
            .foregroundStyle(isSelected ? Theme.selectedInk : Theme.textSecondary)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            // The cap sinks under the finger, so its CONTENT has to travel
            // with it or the label floats off the key it belongs to.
            .offset(y: isSelected && isSinking ? travel : 0)
            .animation(Theme.Anim.press, value: isSinking)
        }
        .buttonStyle(.plain)
        // ⚠️ `@GestureState`, so a cancelled touch clears the latch on its own
        // — a plain `@State` would strand the cap sunk if the finger left
        // without a tap (the ui-interaction.md latch law).
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($pressedIndex) { _, state, _ in state = index }
        )
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("findScope-\(option.rawValue)-\(instanceKey)")
    }
}
