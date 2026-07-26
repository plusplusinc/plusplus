import SwiftUI

/// The catalog scope picker, riding in the TabView's bottom accessory while
/// search is active.
///
/// The tab bar is the scope control the rest of the time (Routines · Exercises ·
/// Kit are tabs again as of 2026-07-26). But the search-role tab spends its
/// selection on search itself, so while you're searching there has to be
/// something else that says which catalog you're searching — this.
///
/// **It is the NATIVE `Picker(.segmented)`, and hand-rolling it was a dead end**
/// (Dave, 2026-07-26, after builds 137–139 went round this three times). The
/// iOS 26 "bubbly" interactive glass — the selection that stretches and settles
/// under your thumb — is available to exactly two components, tab bars and
/// SEGMENTED CONTROLS. Nothing an app draws itself can reproduce it: the
/// hand-rolled row got a `matchedGeometryEffect` pill that didn't even travel
/// (the accessory is a system-owned container that re-renders outside the app's
/// animation transactions), and a material fill that read as neither glass nor
/// platter. `ryanashcraft/FabBar`, recreating this same effect faithfully, ends
/// up hosting a real `UISegmentedControl` and overlaying custom labels on it —
/// which is the tell that the effect is the control's, not the styling's.
///
/// **The "double background" that got the Picker rejected in build 137 was
/// self-inflicted.** The accessory always draws a Liquid Glass capsule and
/// there is no API to remove it; the 137 version then added
/// `.padding(.horizontal, 12)`, which inset the Picker's own segmented track
/// INSIDE that capsule — two concentric shapes, a box in a box. Edge to edge
/// the two silhouettes coincide and read as one control, which is how Photos'
/// Years/Months/All sits in this same slot.
///
/// ⚠️ If a doubled background survives even edge-to-edge, the documented
/// fallback is Apple DTS's answer on forums thread 803030: render the Picker
/// ONLY in `.inline` placement (where the accessory merges into the bar row and
/// brings no capsule of its own) and put something else in `.expanded`. That
/// sample also sets `.tabViewStyle(.sidebarAdaptable)`, which the engineer
/// called essential — worth trying before concluding the Picker can't live here.
struct ScopeSegmentedAccessory: View {
    @Binding var scope: FindScope

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    private var showsLabels: Bool { placement != .inline }

    var body: some View {
        Picker("Catalog", selection: $scope) {
            ForEach(FindScope.allCases, id: \.self) { item in
                // Words when there's a row to hold them, glyphs when the
                // control is sharing the bar with a minimized tab bar and a
                // search field — three labels collide in that width.
                if showsLabels {
                    Text(item.label).tag(item)
                } else {
                    Image(systemName: item.symbolName)
                        .accessibilityLabel(item.label)
                        .tag(item)
                }
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        // NO horizontal padding, deliberately — see the note above. The track
        // has to fill the accessory's capsule, not sit inside it.
        //
        // No `.tint` either: in the accessory the control wears the iOS 26
        // system look rather than the app's selection blue, the same call the
        // other three native segmented pickers took (2026-07-24).
        //
        // Chrome that has to hold three labels on one row can't grow without
        // bound. The search field is NOT capped — its text is the user's own.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}
