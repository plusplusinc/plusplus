import SwiftUI

/// The catalog scope picker: a native segmented control, ALWAYS VISIBLE, in the
/// first row of the search root's pinned section header (Dave, 2026-08-04:
/// "scope bar always visible"). Un-retired from the 2026-08-04 native-scopes
/// round, and relocated — it spent 2026-07-26 to 2026-08-04 in the navigation
/// bar's `.principal` slot.
///
/// ⚠️ **Why it is here and not native `.searchScopes`.** Native scopes belong to
/// the search PRESENTATION: `.onSearchPresentation` draws them when search opens
/// and takes them away when it closes, and there is no "always" activation. The
/// only way to keep them up is to keep search presented, which collapses the
/// large title — and the large title IS the heading that names the catalog
/// (Dave, same round). The two requirements are jointly unsatisfiable natively,
/// so the app draws the control and native `.searchScopes` is not used at all.
///
/// ⚠️ **Why the SECTION HEADER and not a top `safeAreaInset`.** A pinned top
/// inset costs the system large title outright — no title at rest, a
/// title-sized dead band, a hairline in both states (#521, build 162; the law
/// is in `catalog-scopes.md` and `today-rail.md`). A section header lives
/// inside the list's own layout, where the navigation bar never sees it, so
/// the title behaves and the control still pins. It shares that one pin with
/// the facet row: `.listStyle(.plain)` pins one header at a time, so both rows
/// live in the same header rather than competing for it.
///
/// **The rules that survived seven builds of placement, and that this obeys:**
/// - ⚠️ **Do NOT hand-roll the segmented control.** iOS 26's interactive
///   "bubbly" glass belongs to exactly two components, tab bars and segmented
///   controls, so an app-drawn one cannot look native however it is styled
///   (`ryanashcraft/FabBar` hosts a real `UISegmentedControl` for this reason).
///   Build 138 proved the corollary: app-authored animation does not survive
///   inside a system-owned container, so even the canonical
///   `matchedGeometryEffect` pill refused to travel on device.
/// - **WORDS now, not glyphs.** The glyph-only law was a WIDTH constraint of
///   the `.principal` slot — three words could not fit beside the ++ key and a
///   variable-width kit switcher, and a `UISegmentedControl` segment takes a
///   title OR an image, never both (DTS, forums 816517). A full-width row in
///   the list's header has room for all three, a word needs no
///   `accessibilityLabel` to be spoken correctly, and the heading above says
///   the same word — so the selected segment and the title agree.
struct ScopeSegmentedControl: View {
    @Binding var scope: FindScope

    var body: some View {
        Picker("Catalog", selection: $scope) {
            ForEach(FindScope.allCases, id: \.self) { item in
                // The scope's own word, which is also the heading above the
                // list — see the WORDS note in this file's header for why the
                // glyph-only law was a `.principal`-slot width constraint and
                // does not bind in a full-width row.
                Text(item.label).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        // The selected segment takes the PAGE colour, so it reads as part of
        // the surface rather than floating on it (Dave, 2026-07-26 — he asked
        // for the tab bar's darker selection). ⚠️ That only produces a dark
        // pill in DARK mode: `Theme.background` is white in light mode, where
        // this lands on the stock lighter-selection look instead. Both read
        // correctly, because the system's own track sits between the page and
        // the pill either way. Build 146 dropped the tint reasoning the pill
        // would vanish into the row — which ignored that track.
        .tint(Theme.background)
        // ⚠️ Still capped, and the reason MOVED rather than expired. In the
        // bar it was "chrome sharing a row with two keys can't grow without
        // bound"; here it is that a segmented control does not scroll or wrap,
        // it TRUNCATES — so at accessibility sizes three words become three
        // ellipses and the control stops naming anything. The search field is
        // NOT capped: its text is the user's own.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        // ⚠️ NO `.accessibilityIdentifier` here. `SmokeTests.selectScope`
        // reaches the SEGMENTS through `app.segmentedControls.firstMatch
        // .buttons`, and testing.md records that accessibility modifiers on a
        // multi-child container can flatten it and take its children out of
        // XCUITest's tree. An identifier nothing queries would be pure risk on
        // the exact path the suite walks.
    }
}
