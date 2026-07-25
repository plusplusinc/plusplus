import SwiftUI
import PlusPlusKit

/// The app's bottom chrome (2026-07-25, Dave): the four tabs and the search
/// affordance in one bar that CHANGES SHAPE instead of swapping places.
///
/// At rest it reads as it always has — Today · Routines · Exercises · Kit in a
/// platter, the search key separated to their right. Activating search expands
/// the field LEFTWARD, absorbing the space of Routines / Exercises / Kit but
/// NOT Today: Today holds its place beside the field, and the three absorbed
/// tabs rise into a second row above as the search's scope selector, carrying
/// their result counts.
///
/// The taxonomy is the point. **Today is a tab; the other three are scopes.**
/// Today holds a timeline of derived state, not a list of typed items, so it
/// has nothing to search and never becomes a scope — and because it never
/// leaves the bar, it stays the one-tap way out of search. The three catalogs
/// ARE lists of typed items, so they are exactly what a query narrows.
///
/// The tab↔scope move is one `matchedGeometryEffect` per scope, so each label
/// travels from its tab slot to its chip slot rather than cross-fading — the
/// absorb reads as a move, which is what makes the two states legible as one
/// control. `Theme.Anim.selection` resolves near-instant under Reduce Motion.
///
/// This replaces the native `TabView` bar (build 10's trade, knowingly
/// reopened): the system morph is all-or-nothing — it takes the whole bar —
/// so a pinned Today and a scope row above it can only be composed here.
/// Retiring `Tab(role: .search)` also retires the documented iOS 26 morph bug
/// (`.onGeometryChange` in a TabView subtree, nav-diag 4e) along with it.
struct AppBottomBar: View {
    @Binding var tab: AppTab
    @Binding var searching: Bool
    @Binding var query: String
    @Binding var scope: FindScope
    /// Today's tab glyph reflects whether the day holds anything (`TodayStatus`).
    let todaySymbol: String
    /// Per-scope result counts for the live query; empty when there's nothing
    /// to count, so the labels stay bare until a query exists.
    let counts: [FindScope: Int]
    /// One-shot focus intent handed to the field (the `SearchFieldBody` contract).
    @Binding var fieldWantsFocus: Bool
    /// Return key — opens the top result.
    var onSubmit: () -> Void

    @Namespace private var morph

    var body: some View {
        VStack(spacing: 8) {
            if searching {
                scopeRow
            }
            HStack(spacing: 10) {
                platter
                searchAffordance
                if searching {
                    cancelKey
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        // Chrome that must hold four labels plus a field on one row can't grow
        // without bound — the same bargain the system tab bar makes. Content
        // above is unaffected; only the bar caps.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background(alignment: .top) {
            Rectangle()
                .fill(Theme.border)
                .frame(height: 0.5)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .background(.regularMaterial)
    }

    // MARK: - Rows

    /// The absorbed tabs, now scopes. Each carries its match count, so a hit in
    /// a scope you aren't looking at advertises itself on the control that
    /// switches to it — this is what replaced the retired All lens.
    private var scopeRow: some View {
        HStack(spacing: 8) {
            ForEach(FindScope.allCases, id: \.self) { item in
                scopeChip(item)
            }
            Spacer(minLength: 0)
        }
    }

    /// The tab group. It shrinks to just Today while searching — the field
    /// takes the space the other three vacate.
    private var platter: some View {
        HStack(spacing: 2) {
            todayItem
            if !searching {
                ForEach(FindScope.allCases, id: \.self) { item in
                    tabItem(item)
                }
            }
        }
        .padding(4)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border))
    }

    // MARK: - Items

    private var todayItem: some View {
        Button {
            if searching { exitSearch() }
            tab = .today
        } label: {
            itemLabel(symbol: todaySymbol, title: "Today", selected: tab == .today && !searching)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Today")
        .accessibilityAddTraits(tab == .today && !searching ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("tab-today")
    }

    private func tabItem(_ item: FindScope) -> some View {
        Button {
            tab = item.tab
        } label: {
            itemLabel(symbol: item.symbolName, title: item.label, selected: tab == item.tab)
        }
        .buttonStyle(.plain)
        .matchedGeometryEffect(id: item, in: morph)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(tab == item.tab ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("tab-\(item.rawValue)")
    }

    private func itemLabel(symbol: String, title: String, selected: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
            Text(title)
                // Scales with Dynamic Type (a hard-coded point size wouldn't),
                // but shrinks rather than wraps — four labels have to stay on
                // one row. The bar caps its own growth below.
                .font(.system(.caption2, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(selected ? Theme.textPrimary : Theme.textFaint)
        // Each tab claims an equal share of the platter at rest; while
        // searching only Today remains and takes just the room it needs, so
        // the expanding field gets the rest.
        .frame(maxWidth: searching ? nil : .infinity)
        .frame(minWidth: 54)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private func scopeChip(_ item: FindScope) -> some View {
        let selected = scope == item
        return Button {
            scope = item
        } label: {
            HStack(spacing: 5) {
                Text(item.label)
                    .font(.system(.footnote, weight: .semibold))
                if let count = counts[item] {
                    Text("\(count)")
                        .font(.system(.caption2, weight: .semibold).monospacedDigit())
                        .foregroundStyle(selected ? Theme.onSelected.opacity(0.75) : Theme.textFaint)
                }
            }
            .foregroundStyle(selected ? Theme.onSelected : Theme.textSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                selected ? Theme.selected : Theme.surface,
                in: RoundedRectangle(cornerRadius: Theme.keyRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.keyRadius)
                    .strokeBorder(selected ? Color.clear : Theme.border)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .matchedGeometryEffect(id: item, in: morph)
        .accessibilityLabel(counts[item].map { "\(item.label), \($0) results" } ?? item.label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("findScope-\(item.rawValue)")
    }

    @ViewBuilder
    private var searchAffordance: some View {
        if searching {
            SearchFieldBody(
                config: HeaderSearchConfig(
                    text: $query,
                    prompt: "Search \(scope.label.lowercased())",
                    identifier: "findSearchField"
                ),
                wantsFocus: $fieldWantsFocus,
                onSubmit: onSubmit
            )
            .matchedGeometryEffect(id: Self.fieldID, in: morph)
        } else {
            Button {
                enterSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 52, height: 52)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.border))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .matchedGeometryEffect(id: Self.fieldID, in: morph)
            .accessibilityLabel("Search")
            .accessibilityIdentifier("searchTabButton")
        }
    }

    private var cancelKey: some View {
        Button {
            exitSearch()
        } label: {
            Text("Cancel")
                .font(.system(.subheadline))
                .foregroundStyle(Theme.selected)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("searchCancelButton")
    }

    // MARK: - Activation

    private static let fieldID = "appBottomBarSearchField"

    /// Search opens on the scope matching the tab you were already on — you
    /// searched FROM somewhere, so that's what the query narrows first. From
    /// Today (not a scope) it opens on Routines.
    @MainActor
    private func enterSearch() {
        scope = FindScope(tab: tab) ?? .routines
        withAnimation(Theme.Anim.selection) {
            searching = true
        }
        // Tapping the search key IS the activation, so raising the keyboard
        // here is the user's own intent — not the auto-focus-on-entry that the
        // native field deliberately avoided when search was a whole tab.
        fieldWantsFocus = true
    }

    @MainActor
    private func exitSearch() {
        query = ""
        withAnimation(Theme.Anim.selection) {
            searching = false
        }
    }
}
