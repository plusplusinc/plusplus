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
/// ⚠️ Two modifiers make a segmented control legal in a toolbar at all, and
/// both are non-obvious:
/// - `.sharedBackgroundVisibility(.hidden)` on the `ToolbarItem` — a segmented
///   control brings its own track, so the toolbar's shared glass would wrap it
///   in a second shape (the box-in-a-box that killed the accessory). That
///   modifier is TOOLBAR-ONLY, which is part of why the accessory could never
///   be fixed, and here it finally applies.
/// - `.searchPresentationToolbarBehavior(.avoidHidingContent)` on the search
///   presentation — activating search otherwise tells the navigation bar to
///   clear its content, which now takes the scope control with it.
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
///   control that owned a row to itself. In the navigation bar it has to sit
///   beside the app's raised keys, and the default size is the one that matches
///   their height.
struct ScopeSegmentedControl: View {
    @Binding var scope: FindScope

    var body: some View {
        Picker("Catalog", selection: $scope) {
            ForEach(FindScope.allCases, id: \.self) { item in
                // Icon AND label in one segment (Dave, 2026-07-26), which is
                // not something a segmented picker offers: each segment maps to
                // a `UISegmentedControl` segment, and those take a title OR an
                // image, never both. A `Label` collapses to its title there.
                // An `Image` INTERPOLATED into the `Text` is still one `Text`,
                // so the segment renders glyph + word as a single attributed
                // string — and VoiceOver reads only the word, since the
                // interpolation contributes nothing spoken. Same symbols the
                // tab bar uses, so a scope reads the same in both places.
                Text("\(Image(systemName: item.symbolName)) \(item.label)").tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        // The selected segment goes DARK, so the control reads like the tab
        // bar's own selection (Dave, 2026-07-26). The tab bar's structure is
        // lighter track, DARKER selected pill — and that's what this produces,
        // because the system's track sits between the dark row underneath and
        // the dark pill: row (background) → track (system grey, lighter) →
        // selected (background, dark again). Build 146 dropped this on the
        // reasoning that the pill would match the row it sits on; that ignored
        // the track in between, and left the default lighter-pill look, which
        // is the inverse of the bar it sits above.
        .tint(Theme.background)
        // Chrome that has to hold three labels on one row can't grow without
        // bound. The search field is NOT capped — its text is the user's own.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}
