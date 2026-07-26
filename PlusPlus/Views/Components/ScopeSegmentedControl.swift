import SwiftUI

/// The catalog scope picker: a native segmented control, APP-PLACED as a bottom
/// safe-area inset above the search field (see `SearchPresentation`).
///
/// It is app-placed because every system-owned container failed a different way,
/// across six builds. Recorded so nobody re-walks them:
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
///   ⚠️ If that recipe is ever wanted again, the piece that makes it work is
///   `.sharedBackgroundVisibility(.hidden)` on the ToolbarItem: a segmented
///   control brings its own track, so the toolbar's shared glass would wrap it
///   in a second shape. That modifier is TOOLBAR-ONLY, which is part of why the
///   accessory could never be fixed.
///
/// **The rules that survived all of it, and that this obeys:**
/// - ⚠️ **Do NOT hand-roll the segmented control.** iOS 26's interactive
///   "bubbly" glass belongs to exactly two components, tab bars and segmented
///   controls, so an app-drawn one cannot look native however it is styled
///   (`ryanashcraft/FabBar` hosts a real `UISegmentedControl` for this reason).
///   Build 138 proved the corollary: app-authored animation does not survive
///   inside a system-owned container, so even the canonical
///   `matchedGeometryEffect` pill refused to travel on device.
/// - `.controlSize(.large)` gives the Photos proportions.
struct ScopeSegmentedControl: View {
    @Binding var scope: FindScope

    var body: some View {
        Picker("Catalog", selection: $scope) {
            ForEach(FindScope.allCases, id: \.self) { item in
                Text(item.label).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
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
