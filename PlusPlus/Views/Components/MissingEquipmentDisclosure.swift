import SwiftUI

/// The collapsible "N exercises require more equipment" disclosure header
/// (2026-07-25). Replaces the kit-availability FILTERS (the Find-or-create
/// "Doable" chip and the Exercises tab's Equipment facet): instead of hiding
/// what the active kit can't do, every list keeps those items but tucks them
/// under this header, AFTER the doable ones, collapsed by default. The rows
/// inside still carry their own amber "needs X" tags — this header is
/// deliberately NEUTRAL (secondary ink, not amber): amber is the advisory on
/// each row, and an amber header would read as an alarm over a whole group.
///
/// It is a plain scrolling ROW (not a pinned `List` section header) so the
/// disclosure moves with the content. The whole row toggles; the caller owns
/// the (ephemeral, collapsed-by-default) expansion state and wraps the toggle
/// in `withAnimation(Theme.Anim.standard)`.
struct MissingEquipmentHeaderRow: View {
    /// The full count of items behind the disclosure.
    let count: Int
    /// The singular item noun: "exercise" / "routine".
    let noun: String
    let isExpanded: Bool
    /// Disambiguates the a11y identifier across the surfaces that use it.
    var identifier: String = "missingEquipmentToggle"
    let onToggle: () -> Void

    private var label: String {
        MissingEquipmentPhrasing.header(count: count, noun: noun)
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Text(label)
                Spacer(minLength: 8)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(.caption2, weight: .bold))
            }
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel("\(label), \(isExpanded ? "expanded" : "collapsed")")
        .accessibilityAddTraits(.isButton)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
}

/// The one place the disclosure sentence + its pluralization live, so every
/// surface reads identically. "N exercises require more equipment" describes
/// the ITEMS (they require the equipment), not an obligation on the user —
/// clear of the no-obligation copy law, and it mirrors the row-level "needs X".
enum MissingEquipmentPhrasing {
    static func header(count: Int, noun: String) -> String {
        count == 1
            ? "1 \(noun) requires more equipment"
            : "\(count) \(noun)s require more equipment"
    }
}
