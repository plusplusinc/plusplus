import SwiftUI

/// The catalog scope picker: a native segmented control, hosted as a
/// **`.bottomBar` toolbar item** on the search surface.
///
/// This is the Photos Years/Months/All recipe (r/SwiftUI 1o2vdp4), and it is
/// where this control ended up after six builds of trying everywhere else:
///
/// - **`tabViewBottomAccessory` (builds 137–139, 144).** Right position, wrong
///   container. The accessory does NOT rise with the keyboard, so the moment
///   search's keyboard came up the control was buried — and on this surface the
///   keyboard is up most of the time you'd want to change scope.
/// - **Native `.searchScopes` (builds 140–143).** The system's own answer, and
///   it renders exactly ONCE per app run on a bottom-aligned field morphed out
///   of a `Tab(role: .search)`. Tried with `.onSearchPresentation`, with
///   `.searchable` moved inside the navigation stack, with a real navigation
///   bar under it, and with search activating on tab selection so every arrival
///   is a fresh presentation. Still once. It also renders at the TOP, nowhere
///   near the field it scopes.
///
/// A `.bottomBar` toolbar tracks the keyboard, which is the whole reason to be
/// here rather than in the accessory.
///
/// **The rules that survived all of it, and that this obeys:**
/// - ⚠️ **`.sharedBackgroundVisibility(.hidden)` on the hosting `ToolbarItem`**
///   is what stops the double background. A toolbar item otherwise sits in the
///   toolbar's shared glass, and a segmented control brings its own track —
///   two concentric shapes, the box-in-a-box Dave rejected in build 137. That
///   modifier exists precisely to exclude an item that brings its own
///   background, and it is TOOLBAR-ONLY, which is part of why the accessory
///   could never be made to work.
/// - ⚠️ **Do NOT hand-roll the segmented control.** iOS 26's interactive
///   "bubbly" glass belongs to exactly two components, tab bars and segmented
///   controls, so an app-drawn one cannot look native however it is styled
///   (`ryanashcraft/FabBar` hosts a real `UISegmentedControl` for this reason).
///   Build 138 proved the corollary: app-authored animation does not survive
///   inside a system-owned container, so even the canonical
///   `matchedGeometryEffect` pill refused to travel on device.
/// - `.controlSize(.large)` gives the Photos proportions.
/// - `.tint(Theme.background)` makes the SELECTED segment dark in dark mode and
///   white in light — the inversion the tab bar draws for its selected tab
///   (Dave, 2026-07-26). The system default is a lighter grey than the chrome
///   around it, which reads backwards.
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
        .tint(Theme.background)
        // Chrome that has to hold three labels on one row can't grow without
        // bound. The search field is NOT capped — its text is the user's own.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}
