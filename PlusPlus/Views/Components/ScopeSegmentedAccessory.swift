import SwiftUI

/// The catalog scope picker, riding in the TabView's bottom accessory.
///
/// With two tabs — Today and Search — the three catalogs stopped being tabs and
/// became a SCOPE you pick (Dave, 2026-07-25).
///
/// **It draws no background of its own** (Dave, 2026-07-26). A
/// `Picker(.segmented)` brings its own segmented backing, which inside the
/// accessory's glass capsule read as a box in a box. So this is three plain
/// labels with a pill on the selected one, sitting directly on the glass the
/// accessory already provides — the same relationship the system's own tab
/// platter draws between its items and the bar beneath them.
///
/// **It is present on BOTH tabs**, not just Search (Dave). That means it can be
/// tapped while Today is showing, where a scope on its own would do nothing
/// visible — so picking one also takes you to the tab that shows catalogs. The
/// value only ever means "which catalog search is looking at"; where you ARE is
/// the tab's job, and this keeps those two in agreement.
struct ScopeSegmentedAccessory: View {
    @Binding var scope: FindScope
    /// Go to the catalogs. Called for every tap, including a re-pick of the
    /// segment already selected — which changes no value, and would otherwise
    /// strand you on Today.
    var onPick: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FindScope.allCases, id: \.self) { item in
                segment(item)
            }
        }
        .padding(.horizontal, 12)
        // Chrome that has to hold three words on one row can't grow without
        // bound. The search field is NOT capped — its text is the user's own.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func segment(_ item: FindScope) -> some View {
        let selected = scope == item
        return Button {
            scope = item
            onPick()
        } label: {
            Text(item.label)
                .font(.system(.subheadline, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                // The accessory row is short, so this is the whole of its
                // height — a 44 pt target would fight the bar's own sizing.
                .frame(minHeight: 34)
                .background {
                    if selected {
                        Capsule().fill(.thinMaterial)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("scope-\(item.rawValue)")
    }
}
