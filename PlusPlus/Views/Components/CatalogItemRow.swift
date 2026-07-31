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

/// The row-scale entrance flash (cross-surface landings): an accent mark in
/// the row's LEADING MARGIN that grows from its centre, holds, and fades.
///
/// ⚠️ It is a row BACKGROUND, never an overlay (Dave, 2026-07-28). What it
/// replaces was `RoutineCard`'s ring choreography at row scale, and that
/// stopped working the moment the catalogs went cardless: a rounded stroke
/// traces a boundary no other row in the list has, so it read as a state
/// badge rather than a pointer. Its `.padding(.horizontal, -6)` was the
/// tell — an overlay guessing at bounds it cannot see, which is also what
/// put the stroke 2 pt off the text. A row background gets the row's TRUE
/// bounds for free, and the mark lives in the one strip of the row that
/// never holds content, so it cannot crowd a one-line routine or a
/// three-pill one. It also sits UNDER the swipe actions, so a flash caught
/// mid-swipe can't fight `swipeAdd`/`swipeDelete` the way an overlay did.
///
/// Deliberately NOT gated on Reduce Motion — it carries "which row landed",
/// the same call the card ring made. Only the vertical bloom is dropped
/// there; the mark still appears and fades.
struct RowEntranceFlash: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Opacity, and the vertical grow. Separate drivers because the mark
    /// blooms IN and then fades without retracting — one shared value would
    /// shrink it back on the way out, which reads as a cancel.
    @State private var ink: Double = 0
    @State private var bloom: CGFloat = 0.15

    /// Both sit OUTSIDE the 16 pt content column, which is the point.
    private static let markWidth: CGFloat = 3
    private static let markInset: CGFloat = 5

    /// The beat, in seconds — ONE set of numbers driving both the sleeps and
    /// the curves, so a retune can't leave an animation longer than the sleep
    /// that waits on it.
    private static let settle: Double = 0.34
    private static let grow: Double = 0.22
    private static let hold: Double = 0.62
    private static let fade: Double = 0.90

    /// ⚠️ How long the flash needs from MOUNT to finished. The surface that
    /// owns the arrival identity must hold it at least this long: clearing
    /// early unmounts the row background mid-fade, and the mark vanishes
    /// instead of fading. It lives here so the two can't drift apart.
    static let totalDuration: Duration = .seconds(settle + grow + hold + fade)

    var body: some View {
        HStack(spacing: 0) {
            Capsule()
                .fill(Theme.accent)
                .frame(width: Self.markWidth)
                .padding(.vertical, 5)
                .padding(.leading, Self.markInset)
                .scaleEffect(y: bloom, anchor: .center)
                .opacity(ink)
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
        // `.task` is lifecycle-bound: leaving the surface cancels it, so the
        // hand-rolled task handle + `onDisappear` cancel this replaced are
        // no longer needed.
        .task {
            // Let the landing scroll settle before the mark shows.
            try? await Task.sleep(for: .seconds(Self.settle))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: Self.grow)) {
                ink = 1
                bloom = 1
            }
            try? await Task.sleep(for: .seconds(Self.grow + Self.hold))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: Self.fade)) { ink = 0 }
        }
        .onAppear {
            // No travel under Reduce Motion: the mark is already full height
            // and only the opacity carries it.
            if reduceMotion { bloom = 1 }
        }
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

    /// The one word this row leads with: the muscle a lift trains, or the
    /// family a cardio effort belongs to. Cardio has no useful muscle —
    /// the whole catalog files it as Full Body — so the family is the
    /// honest identity there.
    private var identityTag: String {
        exercise.modality.isCardio
            ? exercise.modality.displayName
            : exercise.muscleGroup.displayName
    }

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
                //
                // ⚠️ The row shows the PRIMARY group only, even though an
                // exercise now carries several (2026-07-28). Leading the row
                // with three muscle capsules is exactly what would push the
                // amber gear into "N more" and break the rule above, and a
                // row is an identity line: the primary is what the move IS.
                // The full set reads on the detail screen and the planning
                // sheet, and search reaches every group either way.
                //
                // ⚠️ Except on cardio, where the primary group is a LIE of
                // omission: every cardio exercise is filed `fullBody`, so
                // Running wore a tag reading "Full Body" — true, useless,
                // and actively misleading next to a row of lifts wearing
                // the muscle they train. The movement family is what a run
                // IS, so it takes the slot.
                OverflowCapsuleRow(capsules: [CardCapsule(text: identityTag)]
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
