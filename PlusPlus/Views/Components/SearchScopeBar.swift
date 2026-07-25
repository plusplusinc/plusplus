import SwiftUI
import PlusPlusKit

/// The search scopes — Routines · Exercises · Kit — as a single row, each
/// carrying its match count for the live query.
///
/// These are the app's three CATALOG TABS in their other form. When the native
/// search field takes over the tab bar, they ride ABOVE it (as the TabView's
/// bottom accessory) rather than disappearing with the rest of the bar, so the
/// tabs you were browsing stay the thing you're narrowing. Today is absent by
/// design: it holds a timeline of derived state, not a list of typed items, so
/// there is nothing in it to search.
///
/// The counts are what replaced the retired All lens — a hit in a scope you
/// aren't looking at advertises itself on the very control that switches to it,
/// so the results list needs no cross-scope link rows. No number shows until
/// there's a query to count.
struct SearchScopeBar: View {
    @Binding var scope: FindScope
    let counts: [FindScope: Int]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(FindScope.allCases, id: \.self) { item in
                chip(item)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        // Three chips have to stay on one row; the search field below is
        // unaffected, so the text the user types still scales all the way.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func chip(_ item: FindScope) -> some View {
        let selected = scope == item
        return Button {
            scope = item
        } label: {
            HStack(spacing: 5) {
                Text(item.label)
                    .font(.system(.footnote, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
            // The painted chip stays compact; the TARGET clears the 44 pt floor.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The segmented-control model the scope wheel established: each option
        // is a labelled button carrying `.isSelected`, so VoiceOver reads
        // "Exercises, 12 results, selected, button" and Voice Control can name it.
        .accessibilityLabel(counts[item].map { "\(item.label), \($0) results" } ?? item.label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("findScope-\(item.rawValue)")
    }
}
