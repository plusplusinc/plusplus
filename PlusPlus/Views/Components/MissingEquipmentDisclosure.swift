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
    /// Overrides the equipment sentence for a disclosure that groups by
    /// something else — today only "not rated" (#507, Q14-A). The SHAPE
    /// is the point: narrowed, never vanished, describing the ITEMS
    /// rather than the user (the no-obligation law).
    var sentence: String? = nil
    let onToggle: () -> Void

    private var label: String {
        sentence ?? MissingEquipmentPhrasing.header(count: count, noun: noun)
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

/// The "not rated" disclosure's one sentence (#507, Q14-A). Effort and
/// Style are catalog ratings, so a routine with no catalog template
/// simply has none — the sentence states that about the ROUTINES, never
/// about the user, and never as something to fix.
///
/// ⚠️ It says nothing about WHO made them. "routines you built" was
/// false for an imported one (`ShareImportSheet` produces routines with
/// no `catalogTemplate` too), and provenance was never the point
/// (swift-reviewer).
enum UnratedPhrasing {
    static func line(count: Int) -> String {
        count == 1
            ? "1 routine has no effort or style rating"
            : "\(count) routines have no effort or style rating"
    }
}
