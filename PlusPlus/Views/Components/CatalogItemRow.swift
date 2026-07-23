import SwiftUI
import PlusPlusKit

/// Shared catalog item representation (2026-07-18, Dave): codifies the
/// design vocabulary so an exercise or a piece of gear reads the SAME way
/// wherever it appears — the catalog, the active kit list, the picker —
/// with only necessary exceptions. Three pieces:
/// - `CardTagCapsule` — a soft, non-interactive data capsule.
/// - `ExerciseRowContent` — the exercise row body (catalog + picker).
/// - `EquipmentRowContent` — the equipment row body (catalog + kit list).

/// A soft, non-interactive data tag for cards and rows: the property a filter
/// or sort controls appears on the items it narrows, in the SAME tag so the
/// two visibly connect. A soft `surfaceRaised` fill and NO stroke, because a
/// stroked tag reads as a button and these aren't buttons; a soft rounded
/// rectangle, not a pill, so it shares the filter controls' shape language
/// (Dave, 2026-07-20). Natural-case, standard (non-mono) caption text — the
/// mono was retired 2026-07-20; all-caps stays reserved for section labels.
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
    /// An optional leading SF Symbol (the schedule capsule's calendar glyph).
    /// Sits inside the same capsule so the tag reads as one unit.
    var systemImage: String? = nil

    /// The tag's horizontal padding, shared with `CardCapsule`'s width
    /// measurement so the single-line overflow row can predict the fit.
    static let horizontalPadding: CGFloat = 8
    /// A soft rounded rectangle, not a pill (Dave, 2026-07-20): the filter
    /// controls became rounded rects, so the data tags follow into one shape
    /// language. The radius is smaller than the r11 controls because the tag
    /// is short — r11 on a ~19 pt tag would render as a full capsule; ~6
    /// keeps the controls' corner-to-height proportion.
    static let cornerRadius: CGFloat = 6

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(.caption2))
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .font(.system(.caption2))
        .foregroundStyle(tint)
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, 2.5)
        .background(fill, in: RoundedRectangle(cornerRadius: Self.cornerRadius))
        .lineLimit(1)
        .fixedSize(horizontal: holdsWidth, vertical: false)
    }
}

/// The row-scale entrance flash (universal-search landings): an inset
/// accent ring that appears after a beat and fades out — RoutineCard's
/// ring choreography at row scale. Pure opacity, deliberately NOT gated
/// on Reduce Motion (it carries "which row landed", the same call as the
/// card ring). Mount it as a row overlay while the row is the arrival.
struct RowEntranceFlash: View {
    @State private var entrance: Double = 0
    @State private var flashTask: Task<Void, Never>?

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.controlRadius)
            .strokeBorder(Theme.accent, lineWidth: 2)
            // The ring hugs the row content but breathes past the list
            // insets sideways, so it reads as a frame, not a squeeze.
            .padding(.vertical, 2)
            .padding(.horizontal, -6)
            .opacity(entrance)
            .allowsHitTesting(false)
            .onAppear {
                flashTask?.cancel()
                flashTask = Task {
                    // Let the landing scroll settle before the ring shows.
                    try? await Task.sleep(for: .milliseconds(340))
                    guard !Task.isCancelled else { return }
                    entrance = 1
                    withAnimation(.easeOut(duration: 0.9)) { entrance = 0 }
                }
            }
            .onDisappear { flashTask?.cancel() }
    }
}

/// The row NAME with a query's literal match painted in the selection
/// wash — the universal-search highlight. Ranges come from
/// `FuzzySearch.highlightRanges` against the same string; anything that
/// fails to map (a stale range after an edit) paints nothing.
func highlightedName(_ text: String, ranges: [Range<String.Index>]) -> AttributedString {
    var result = AttributedString(text)
    for range in ranges {
        guard let lower = AttributedString.Index(range.lowerBound, within: result),
              let upper = AttributedString.Index(range.upperBound, within: result),
              lower < upper else { continue }
        result[lower..<upper].backgroundColor = Theme.selectedTint
    }
    return result
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
    /// Optional leading type/modality glyph (universal-search rows) —
    /// 16 pt faint ink, a type marker, not a control.
    var leadingSymbol: String? = nil
    /// Match ranges in `exercise.name` to paint (universal search).
    var nameHighlight: [Range<String.Index>] = []

    var body: some View {
        HStack(spacing: 10) {
            if let leadingSymbol {
                Image(systemName: leadingSymbol)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textFaint)
                    .frame(width: 22)
                    .accessibilityHidden(true)
            }
            if exercise.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            }
            // The VStack claims the row's free width (maxWidth: .infinity) so
            // the capsule row inside gets a real width to fit against — a
            // trailing Spacer would otherwise split that width with it and
            // halve the capsule room. The trailing Custom tag + chevron keep
            // their intrinsic size and ride the right edge.
            VStack(alignment: .leading, spacing: 6) {
                Text(highlightedName(exercise.name, ranges: nameHighlight))
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Muscle + gear as one capsule row (2026-07-19): gear reads
                // the same soft tag as everywhere else, amber-washed when the
                // active kit lacks it. Amber sorts first, so the "N more"
                // overflow can only ever drop an available piece — the
                // missing-gear flag stays visible (#113 flag-don't-hide).
                OverflowCapsuleRow(capsules: [CardCapsule(text: exercise.muscleGroup.displayName)]
                    + RoutineCardCapsules.gearCapsules(gear))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    /// The gear an exercise needs, paired with whether the active kit has
    /// each (amber-flag input). A bodyweight exercise shows one neutral
    /// "Bodyweight" tag.
    private var gear: [(name: String, available: Bool)] {
        let items = exercise.equipment.filter { !$0.isDeleted }.map(\.name)
        guard !items.isEmpty else { return [(name: "Bodyweight", available: true)] }
        return items.map { (name: $0, available: available.contains($0)) }
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
    /// Optional leading type glyph (universal-search rows) — 16 pt faint
    /// ink, a type marker, not a control.
    var leadingSymbol: String? = nil
    /// Match ranges in `equipment.name` to paint (universal search).
    var nameHighlight: [Range<String.Index>] = []

    var body: some View {
        HStack(spacing: 10) {
            if let leadingSymbol {
                Image(systemName: leadingSymbol)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textFaint)
                    .frame(width: 22)
                    .accessibilityHidden(true)
            }
            // The VStack claims the row's free width (maxWidth: .infinity) so
            // the name has full room and short names don't wrap. A trailing
            // Spacer instead let the name size to its ideal, and the in-kit
            // checkmark tightened the width proposal enough to tip a
            // medium-length name (e.g. "Resistance Band") onto two lines while
            // longer checkmark-less rows stayed on one. Matches ExerciseRowContent.
            VStack(alignment: .leading, spacing: 6) {
                Text(highlightedName(equipment.name, ranges: nameHighlight))
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    kindCapsule
                    if unlockedCount > 0 {
                        CardTagCapsule(text: "\(unlockedCount) exercise\(unlockedCount == 1 ? "" : "s")")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
