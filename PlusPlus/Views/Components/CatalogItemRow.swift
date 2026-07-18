import SwiftUI
import PlusPlusKit

/// Shared catalog item representation (2026-07-18, Dave): codifies the
/// design vocabulary so an exercise or a piece of gear reads the SAME way
/// wherever it appears — the catalog, the active kit list, the picker —
/// with only necessary exceptions. Three pieces:
/// - `CardTagCapsule` — a soft, non-interactive data capsule.
/// - `ExerciseRowContent` — the exercise row body (catalog + picker).
/// - `EquipmentRowContent` — the equipment row body (catalog + kit list).

/// A soft, non-interactive data capsule for cards and rows: the property a
/// filter or sort controls appears on the items it narrows, in the SAME
/// capsule so the two visibly connect. It wears the routine cards' gear-pill
/// style — a soft `surfaceRaised` fill and NO stroke, because a stroked
/// capsule reads as a button and these aren't buttons. (All-caps is reserved
/// for section labels; this is natural-case mono metadata.)
struct CardTagCapsule: View {
    let text: String
    var tint: Color = Theme.textSecondary
    /// Defaults to the soft neutral fill; an amber wash flags a gap (a
    /// routine's gear the active kit doesn't have).
    var fill: Color = Theme.surfaceRaised
    /// A lone data capsule holds its width so a sibling label truncates
    /// instead of squishing the tag. The routine-card pill row passes false
    /// so its several pills compress together, as they did before.
    var holdsWidth: Bool = true

    var body: some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 2.5)
            .background(fill, in: Capsule())
            .lineLimit(1)
            .fixedSize(horizontal: holdsWidth, vertical: false)
    }
}

/// The shared exercise row body: the SAME representation in the Exercises
/// catalog and the picker. Star = favorited, a muscle capsule (↔ the Muscle
/// filter), the gear it needs with the missing-gear gap flagged amber
/// (↔ the Gear filter), and a Custom tag. The chevron is the one context
/// exception — the catalog pushes to detail, the picker selects — so it is
/// opt-out. Swipe actions / tap targets stay with each call site.
struct ExerciseRowContent: View {
    let exercise: Exercise
    /// Active-kit gear names, for the "needs X" availability flag.
    let available: Set<String>
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 10) {
            if exercise.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    CardTagCapsule(text: exercise.muscleGroup.displayName)
                    Text(gearText)
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                // The missing-gear flag rides its OWN line so it can't be
                // truncated off the end of the gear list (#113 flag-don't-hide).
                if !missing.isEmpty {
                    Text("needs \(missing.joined(separator: ", "))")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.notes)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if !exercise.isBuiltIn {
                CardTagCapsule(text: "Custom", tint: Theme.accent)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// The gear an exercise needs (or "Bodyweight"); truncates on its line.
    private var gearText: String {
        let names = exercise.equipment.map(\.name).sorted().joined(separator: ", ")
        return names.isEmpty ? "Bodyweight" : names
    }

    /// Active-kit gear gap, flagged in notes amber (flag-don't-hide, #113).
    private var missing: [String] {
        ExerciseFilterState.missingEquipment(for: exercise, available: available)
    }
}

/// The shared equipment row body: the SAME representation in the Equipment
/// catalog and the active kit list. A category capsule (↔ the Type filter)
/// and an "N exercises" capsule (↔ the Most-exercises sort); customs show a
/// Custom tag instead of a category. The in-kit glyph is the necessary
/// exception — the catalog marks membership, the kit list is all-in-kit so
/// it passes nil and omits it.
struct EquipmentRowContent: View {
    let equipment: Equipment
    let unlockedCount: Int
    /// nil = don't show a membership glyph (the kit list, where every row is
    /// in the kit). true/false = show it when in the kit (the catalog).
    var inKit: Bool? = nil
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(equipment.name)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    kindCapsule
                    if unlockedCount > 0 {
                        CardTagCapsule(text: "\(unlockedCount) exercise\(unlockedCount == 1 ? "" : "s")")
                    }
                }
            }
            Spacer(minLength: 8)
            if inKit == true {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(.body))
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("In kit")
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// Category for a built-in (every built-in is categorized), else a
    /// Custom tag — customs carry no catalog category.
    @ViewBuilder private var kindCapsule: some View {
        if let category = SeedData.equipmentCategory(named: equipment.name) {
            CardTagCapsule(text: category.rawValue)
        } else if !equipment.isBuiltIn {
            CardTagCapsule(text: "Custom", tint: Theme.accent)
        }
    }
}
