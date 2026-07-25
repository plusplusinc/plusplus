import SwiftUI
import PlusPlusKit

/// The app's bottom chrome (2026-07-25, Dave's design): three sections, left to
/// right — a floating **Today** key, the **Routines · Exercises · Kit** group,
/// and a floating **Search** key.
///
/// Activating search takes the middle group and MOVES it up into a second row,
/// where it spans the full width; the search field takes the space it left.
/// The group renders identically in both places — same icons, same labels, same
/// selected treatment — because it is the same control in two positions, and it
/// travels between them rather than swapping.
///
/// **The travel is Liquid Glass's own morph**, not a hand-rolled one: the bar is
/// a `GlassEffectContainer`, and the group carries one `glassEffectID` in a
/// shared namespace, whose transition defaults to `.matchedGeometry` — so the
/// MATERIAL morphs between the two positions, not merely the frame.
///
/// The group is ONE glass surface holding three plain items, with a pill on the
/// selected one — the same relationship the system's tab platter draws. An
/// earlier cut gave every item its own glass and unioned them, which is what
/// made the three stop reading as tabs.
///
/// **Why this isn't the system tab bar.** It was, twice. The native bar can't
/// express any of the three requirements: `Tab(role:)` separates only the
/// search item (`.prominent` is OS27 and undocumented), native `Tab` items
/// can't be restyled or spanned, and — decisively — they aren't views the app
/// can address, so they cannot share a geometry namespace and therefore cannot
/// move. The system's own two-placement accessory keys off SCROLL, not search,
/// and its inline placement means a MINIMIZED bar with the other tabs hidden.
/// So this reopens build 10's trade knowingly: the app draws the bar, and owes
/// the hit targets and accessibility the system used to provide.
struct AppBottomBar: View {
    @Binding var tab: AppTab
    @Binding var searching: Bool
    @Binding var query: String
    /// Today's tab glyph reflects whether the day holds anything (`TodayStatus`).
    let todaySymbol: String
    /// Per-scope result counts for the live query; empty when there's nothing
    /// to count, so the labels stay bare until a query exists.
    let counts: [FindScope: Int]
    /// Return key — opens the top result.
    var onSubmit: () -> Void

    @Namespace private var glass

    /// The catalog the group is pointing at. There is ONE source of truth: the
    /// selected tab. Search doesn't introduce a second selection — its scope
    /// row drives the same `tab`, which is what lets the group be one control.
    private var scope: FindScope? { FindScope(tab: tab) }

    var body: some View {
        // Glass FLOATS over content — it never sits on an opaque plate, which
        // is the main tell of custom chrome. So there is no material fill and
        // no hairline here; legibility where content scrolls under comes from
        // the scroll-edge effect, which system bars get free and custom bars
        // must ask for.
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 8) {
            if searching {
                scopeGroup(expanded: true)
            }
            HStack(spacing: 10) {
                todayKey
                if searching {
                    SearchFieldBody(
                        config: HeaderSearchConfig(
                            text: $query,
                            // What the scope SEARCHES, not what its tab is
                            // called: the Kit scope searches the equipment
                            // catalog (kit-vs-equipment vocabulary law).
                            prompt: "Search \(scope?.searchNoun ?? "routines")",
                            identifier: "findSearchField"
                        ),
                        // Never armed: activating search expands the field and
                        // lifts the group, and the keyboard rises only when the
                        // field itself is tapped (Dave, 2026-07-25).
                        wantsFocus: .constant(false),
                        onSubmit: onSubmit
                    )
                    cancelKey
                } else {
                    scopeGroup(expanded: false)
                    searchKey
                }
            }
        }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .scrollEdgeEffectStyle(.hard, for: .bottom)
    }

    // MARK: - The travelling group

    /// The same three items whether they sit in the bar or in the row above —
    /// only the width changes. Expanded, they span the full width.
    private func scopeGroup(expanded: Bool) -> some View {
        // No inter-item spacing: they share ONE platter, so the pill on the
        // selected item is what separates them, exactly as in the system bar.
        HStack(spacing: 0) {
            ForEach(FindScope.allCases, id: \.self) { item in
                scopeItem(item)
            }
        }
        .padding(4)
        .frame(maxWidth: expanded ? .infinity : nil)
        // ONE glass surface for the whole group — the native tab platter is a
        // single pill containing its items, not a row of separate pills.
        .glassEffect(.regular, in: Capsule())
        .glassEffectID(Self.groupID, in: glass)
        // Chrome that must hold three labels on one row can't grow without
        // bound. The search field is NOT capped — its text is the user's own.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func scopeItem(_ item: FindScope) -> some View {
        let selected = tab == item.tab
        return Button {
            tab = item.tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 17, weight: .medium))
                Text(item.label)
                    .font(.system(.caption2, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                // The count rides the label while a query exists — a hit in a
                // scope you aren't looking at advertises itself on the control
                // that switches to it (this is what replaced the All lens).
                if let count = counts[item] {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background {
                // The selected tab's pill, inside the platter — the same
                // relationship the system bar draws.
                if selected {
                    Capsule().fill(.thinMaterial)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(counts[item].map { "\(item.label), \($0) results" } ?? item.label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("tab-\(item.rawValue)")
    }

    // MARK: - The two floating keys

    private var todayKey: some View {
        Button {
            if searching { exitSearch() }
            tab = .today
        } label: {
            Image(systemName: todaySymbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(tab == .today && !searching ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
        }
        // The dedicated glass button style — this is what the system's own
        // separated search circle is, so the two floating keys match it.
        .buttonStyle(.glass)
        .glassEffectID(Self.todayID, in: glass)
        .accessibilityLabel("Today")
        .accessibilityAddTraits(tab == .today && !searching ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("tab-today")
    }

    /// A rounded SQUARE, not a circle: icon-only keys are r11 rounded squares
    /// everywhere (2026-07-19 — the all-circles round was reverted).
    private var searchKey: some View {
        Button {
            enterSearch()
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(.body, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.glass)
        .glassEffectID(Self.searchID, in: glass)
        .accessibilityLabel("Search")
        .accessibilityIdentifier("searchTabButton")
    }

    /// Leaving search is an escape hatch, so it wears the quiet key — blue is
    /// retired as a text colour, and a bare `Text` would give a tap target the
    /// size of the word inside a 52 pt row.
    private var cancelKey: some View {
        QuietKey(label: "Cancel", identifier: "searchCancelButton") {
            exitSearch()
        }
    }

    // MARK: - Activation

    private static let groupID = "appBottomBarScopeGroup"
    private static let todayID = "appBottomBarToday"
    private static let searchID = "appBottomBarSearch"

    /// Search narrows the catalog you're already in. From Today — which is a
    /// tab, never a scope — it opens on Routines.
    @MainActor
    private func enterSearch() {
        if scope == nil { tab = .routines }
        withAnimation(Theme.Anim.selection) {
            searching = true
        }
        // Deliberately NO focus arming: activating search expands the field
        // and lifts the group into its own row — that is the whole gesture.
        // The keyboard rises only when the field itself is tapped (Apple's
        // "search is activated and deactivated by the user", and Dave's ask).
    }

    @MainActor
    private func exitSearch() {
        query = ""
        withAnimation(Theme.Anim.selection) {
            searching = false
        }
    }
}
