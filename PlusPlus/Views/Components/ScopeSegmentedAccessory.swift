import SwiftUI

/// The catalog scope picker, in the TabView's bottom accessory while search is
/// active — which is the position native search scopes could never be talked
/// into occupying.
///
/// **Why we are back here** (Dave, 2026-07-26, after builds 140–143). Native
/// `.searchScopes` is the system's own answer to narrowing a search and it was
/// the right thing to try, but in this configuration — a bottom-aligned field
/// morphed out of a `Tab(role: .search)` — it renders **once**: the scope bar
/// appears the first time search is presented and never again, through
/// `.onSearchPresentation`, through moving `.searchable` inside the navigation
/// stack, through giving the surface a real navigation bar, and through
/// activating search with the tab so every arrival is a fresh presentation. It
/// also renders at the TOP, nowhere near the field it scopes, and placement is
/// not the app's to choose.
///
/// **The lessons from the first accessory round still apply, and this obeys
/// them:**
/// - The accessory ALWAYS draws a Liquid Glass capsule and no API removes it.
///   So the control must FILL that capsule rather than sit inside it — the
///   "double background" Dave rejected in build 137 was `.padding(.horizontal, 12)`
///   insetting the Picker's own segmented track within the accessory's capsule,
///   drawing two concentric shapes. Edge to edge, the silhouettes coincide.
/// - ⚠️ Do NOT hand-roll the segmented control. iOS 26's interactive "bubbly"
///   glass belongs to exactly two components, tab bars and segmented controls,
///   so an app-drawn one cannot look native however it is styled. Build 138
///   proved the second half of that too: app-authored animation does not
///   survive inside the accessory, because it is a system-owned container that
///   re-renders outside the app's transactions — even the canonical
///   `matchedGeometryEffect` pill with `.animation` on the value refused to
///   travel on device.
/// - `.controlSize(.large)` is what gives it the Photos proportions
///   (r/SwiftUI 1o2vdp4).
/// - No `.tint`: in the accessory it wears the iOS 26 system look rather than
///   the app's selection blue, the same call the app's other three native
///   segmented pickers took.
struct ScopeSegmentedAccessory: View {
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
        // NO horizontal padding — see the note above. The track fills the
        // accessory's capsule instead of nesting inside it.
        //
        // Chrome that has to hold three labels on one row can't grow without
        // bound. The search field is NOT capped — its text is the user's own.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}
