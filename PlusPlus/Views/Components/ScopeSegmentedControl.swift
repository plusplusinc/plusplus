import SwiftUI

/// The catalog scope picker: a native segmented control living in the search
/// surface's NAVIGATION BAR, in the principal slot between the ++ key and the
/// kit switcher (Dave, 2026-07-26). That is the same row the other four tab
/// roots put their title in — on this surface the control names the catalog, so
/// it takes the title's place rather than sitting under it.
///
/// It took seven builds and five placements to get here, because every
/// system-owned container failed a different way. Recorded so nobody re-walks
/// them:
///
/// - **`tabViewBottomAccessory` (137–139, 144).** Right position, wrong
///   container: the accessory does NOT rise with the keyboard, so search's own
///   keyboard buried the control — and on this surface the keyboard is up most
///   of the time you'd want to change scope.
/// - **Native `.searchScopes` (140–143).** The system's own answer, and it
///   renders exactly ONCE per app run on a bottom-aligned field morphed out of
///   a `Tab(role: .search)` — tried with `.onSearchPresentation`, with
///   `.searchable` moved inside the navigation stack, with a real navigation
///   bar under it, and with search activating on tab selection so every arrival
///   is a fresh presentation. It also renders at the TOP, nowhere near the
///   field it scopes.
/// - **A `.bottomBar` `ToolbarItem` (145)** — the Photos Years/Months/All
///   recipe (r/SwiftUI 1o2vdp4) — lands in the SAME ROW the search-role tab's
///   field expands into, so it sits behind the field. Photos gets away with it
///   because its search is a small BUTTON in that row, not a full-width field.
///   The `.principal` slot has no such competition: the field expands out of
///   the TAB BAR at the bottom, nowhere near the navigation bar.
/// - **A TOP `safeAreaInset`, under the bar (147).** Correct, and one row too
///   many: a band holding a control sat directly beneath a bar holding two
///   keys, with nothing in the middle of it.
///
/// ⚠️ **`.searchPresentationToolbarBehavior(.avoidHidingContent)` on the search
/// presentation is REQUIRED** — activating search otherwise tells the
/// navigation bar to clear its content, which now takes the scope control with
/// it, not just the keys.
///
/// The item also carries `.sharedBackgroundVisibility(.hidden)`, which is the
/// documented escape for a toolbar item bringing its own background (a
/// segmented control brings its own track, and the toolbar's shared glass would
/// otherwise wrap it in a second shape — the box-in-a-box that killed the
/// accessory). ⚠️ Unverified in the PRINCIPAL slot specifically: the shared
/// background belongs to GROUPED bar items, and the title region may not be one
/// — so if a double shape ever does appear here, this is not necessarily the
/// lever. It matches the two keys either way.
///
/// **The rules that survived all of it, and that this obeys:**
/// - ⚠️ **Do NOT hand-roll the segmented control.** iOS 26's interactive
///   "bubbly" glass belongs to exactly two components, tab bars and segmented
///   controls, so an app-drawn one cannot look native however it is styled
///   (`ryanashcraft/FabBar` hosts a real `UISegmentedControl` for this reason).
///   Build 138 proved the corollary: app-authored animation does not survive
///   inside a system-owned container, so even the canonical
///   `matchedGeometryEffect` pill refused to travel on device.
/// - **No `.controlSize(.large)`.** That was the Photos proportion for a
///   control that owned a row to itself. A large segmented control is taller
///   than the navigation bar it would now sit in, so the default size is the
///   one that fits.
struct ScopeSegmentedControl: View {
    @Binding var scope: FindScope

    var body: some View {
        Picker("Catalog", selection: $scope) {
            ForEach(FindScope.allCases, id: \.self) { item in
                // ⚠️ GLYPH ONLY, and not by preference — on iOS a segmented
                // control CANNOT show an icon and a word in the same segment.
                // `UISegmentedControl` gives each segment a title OR an image,
                // never both (AppKit's `NSSegmentedControl` can; UIKit's can't),
                // and SwiftUI inherits that: Apple DTS answered it directly on
                // forums thread 816517 — `.titleAndIcon` on a segmented picker
                // renders the title and drops the icon, and the HIG says pick
                // one, don't mix. So "icons too" (Dave, 2026-07-26) means icons
                // INSTEAD, and glyphs are the half that survives the bar: three
                // words plus three symbols do not fit the principal slot beside
                // the ++ key and a variable-width kit switcher, and a segmented
                // control does not scroll — it truncates.
                //
                // Nothing is lost: these are the SAME symbols the tab bar uses
                // for the same three scopes, so a scope reads identically in
                // both places, and off search the tab bar carries the words.
                // The explicit label is what VoiceOver reads — without it the
                // system speaks the symbol name ("square stack").
                Image(systemName: item.symbolName)
                    .accessibilityLabel(Text(item.label))
                    .tag(item)
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
        // Chrome on a bar shared with two keys can't grow without bound. The
        // search field is NOT capped — its text is the user's own.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}
