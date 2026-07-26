import SwiftUI

/// The catalog scope picker, riding in the TabView's bottom accessory.
///
/// With two tabs — Today and Search — the three catalogs stopped being tabs and
/// became a SCOPE you pick (Dave, 2026-07-25). This is a plain
/// `Picker(.segmented)`: the custom horizontal wheel that briefly held the job
/// is deleted, so the control is the system's, at the system's sizing, with the
/// system's accessibility.
///
/// **It is present on BOTH tabs**, not just Search (Dave). That means it can be
/// tapped while Today is showing, where a scope on its own would do nothing
/// visible — so picking one also takes you to the tab that shows catalogs. The
/// segmented value only ever means "which catalog search is looking at"; where
/// you ARE is the tab's job, and this keeps those two in agreement.
struct ScopeSegmentedAccessory: View {
    @Binding var scope: FindScope
    /// Go to the catalogs. Called for every tap, including one that re-picks
    /// the segment already selected.
    var onPick: () -> Void

    var body: some View {
        Picker("Catalog", selection: pickerBinding) {
            ForEach(FindScope.allCases, id: \.self) { item in
                Text(item.label).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        // Re-picking the SELECTED segment doesn't change the binding, so the
        // setter alone would strand you on Today whenever the scope you wanted
        // was already the current one. A simultaneous tap catches that case
        // without consuming the control's own handling (the #99 gesture law);
        // both paths do the same idempotent thing.
        .simultaneousGesture(TapGesture().onEnded { onPick() })
        .padding(.horizontal, 12)
        // Chrome that has to hold three words on one row can't grow without
        // bound; the search field is NOT capped, since its text is the user's.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private var pickerBinding: Binding<FindScope> {
        Binding(
            get: { scope },
            set: { newScope in
                scope = newScope
                onPick()
            }
        )
    }
}
