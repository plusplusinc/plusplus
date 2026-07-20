import SwiftUI
import UIKit

/// Shared routine-card vocabulary (2026-07-19, Dave): the catalog card, the
/// library card, and the routine-detail header now read the SAME way — one
/// title, prose that wraps to two lines, and a row of soft `CardTagCapsule`s
/// (schedule · focus · effort · estimate · gear). They vary only where a
/// template genuinely differs from an added routine (a template has no
/// schedule), exactly as an equipment card varies only by its in-kit glyph.
///
/// Two rules ride the capsule row:
/// - CARDS never truncate or wrap a capsule: the tail collapses into a
///   trailing "N more" (`OverflowCapsuleRow`).
/// - The DETAIL header shows the FULL set, wrapping as needed
///   (`DetailHeaderCapsules`).

/// A value describing one `CardTagCapsule`, so a row can measure and lay out
/// its capsules before building the views.
struct CardCapsule {
    var text: String
    var tint: Color = Theme.textSecondary
    var fill: Color = Theme.surfaceRaised
    /// An optional leading SF Symbol (the schedule capsule's calendar glyph).
    var systemImage: String? = nil
    /// A spoken form when the glyph + text reads poorly to VoiceOver.
    var accessibilityText: String? = nil

    func view() -> CardTagCapsule {
        CardTagCapsule(text: text, tint: tint, fill: fill, holdsWidth: true, systemImage: systemImage)
    }

    var spokenText: String { accessibilityText ?? text }

    /// The rendered capsule width, so `OverflowCapsuleRow` can predict the
    /// fit without a measurement pass. Mirrors `CardTagCapsule`'s font
    /// (caption2 monospaced) + horizontal padding; Dynamic-Type aware via the
    /// scaled point size.
    func measuredWidth() -> CGFloat {
        let pointSize = UIFont.preferredFont(forTextStyle: .caption2).pointSize
        let font = UIFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        var width = (text as NSString).size(withAttributes: [.font: font]).width
        if systemImage != nil {
            // The glyph is roughly square at the cap height, plus the HStack's
            // 3 pt spacing. An estimate is fine — only the leading schedule
            // capsule carries a glyph, and it always shows.
            width += pointSize * 1.2 + 3
        }
        width += CardTagCapsule.horizontalPadding * 2
        return ceil(width)
    }
}

/// A single line of capsules that never truncates or wraps: it lays them out
/// left to right and, when they don't all fit, collapses the tail into a
/// trailing "N more" capsule (Dave's rule, 2026-07-19). Container width comes
/// from a background `GeometryReader`, so there is no state feedback loop with
/// the layout pass.
struct OverflowCapsuleRow: View {
    let capsules: [CardCapsule]
    var spacing: CGFloat = 6
    @State private var containerWidth: CGFloat = 0

    var body: some View {
        let result = fitting(width: containerWidth)
        HStack(spacing: spacing) {
            ForEach(result.visible.indices, id: \.self) { index in
                result.visible[index].view()
            }
            if result.overflow > 0 {
                CardTagCapsule(text: "\(result.overflow) more", tint: Theme.textFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, width in containerWidth = width }
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(capsules.map(\.spokenText).joined(separator: ", "))
    }

    /// Greedily fit capsules left to right, reserving room for the "N more"
    /// tag whenever anything is left over. Amber (unavailable-gear) capsules
    /// are placed first by the caller, so overflow can only ever drop an
    /// available one (#113 flag-don't-hide).
    private func fitting(width: CGFloat) -> (visible: [CardCapsule], overflow: Int) {
        guard width > 0, !capsules.isEmpty else { return (capsules, 0) }
        let widths = capsules.map { $0.measuredWidth() }
        var used: CGFloat = 0
        var shown = 0
        for index in capsules.indices {
            let separator: CGFloat = shown == 0 ? 0 : spacing
            let newUsed = used + separator + widths[index]
            let remaining = capsules.count - (shown + 1)
            let reserve = remaining > 0 ? spacing + moreWidth(remaining) : 0
            if newUsed + reserve <= width {
                used = newUsed
                shown += 1
            } else {
                break
            }
        }
        // Always show at least the first capsule, even in a pathological
        // narrow width — better one real tag + "N more" than only "N more".
        if shown == 0 { shown = 1 }
        return (Array(capsules.prefix(shown)), capsules.count - shown)
    }

    private func moreWidth(_ count: Int) -> CGFloat {
        CardCapsule(text: "\(count) more").measuredWidth()
    }
}

/// The full capsule set, wrapping as needed — the routine/exercise/equipment
/// detail headers (Dave, 2026-07-19: the detail top aligns with the cards but
/// always shows the full data, no cap).
struct DetailHeaderCapsules: View {
    let capsules: [CardCapsule]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(capsules.indices, id: \.self) { index in
                capsules[index].view()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(capsules.map(\.spokenText).joined(separator: ", "))
    }
}

/// The shared routine-card body: identity, prose (two lines), and the
/// single-line capsule row. Card chrome (padding, background, the library's
/// entrance flash, the catalog's `Button`) stays at each call site — the same
/// split as `ExerciseRowContent`/`EquipmentRowContent`.
struct RoutineCardModel {
    var title: String
    var prose: String
    /// The library schedule capsule (calendar glyph + cadence). Nil for a
    /// template — the one necessary catalog↔library variation.
    var schedule: CardCapsule?
    var focus: String?
    var effort: String?
    var estimate: String?
    /// Gear names paired with whether the active kit has each.
    var gear: [(name: String, available: Bool)]
}

struct RoutineCardContent: View {
    let model: RoutineCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    // Claim the row width (rather than lean on a trailing
                    // Spacer) so a medium-length name isn't tipped onto two
                    // lines by the chevron's width proposal.
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
                    .accessibilityHidden(true)
            }
            if !model.prose.isEmpty {
                Text(model.prose)
                    .font(.system(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            let capsules = RoutineCardCapsules.build(from: model, includesSchedule: true)
            if !capsules.isEmpty {
                OverflowCapsuleRow(capsules: capsules)
            }
        }
    }
}

/// Builds the ordered capsule set shared by the card and the detail header,
/// so both read the facts in the same order with the same treatment.
enum RoutineCardCapsules {
    static func build(from model: RoutineCardModel, includesSchedule: Bool) -> [CardCapsule] {
        var out: [CardCapsule] = []
        if includesSchedule, let schedule = model.schedule { out.append(schedule) }
        if let focus = model.focus { out.append(CardCapsule(text: focus)) }
        if let effort = model.effort { out.append(CardCapsule(text: effort)) }
        if let estimate = model.estimate { out.append(CardCapsule(text: estimate)) }
        out.append(contentsOf: gearCapsules(model.gear))
        return out
    }

    /// Gear as soft tags, amber-washed when the active kit lacks the piece.
    /// Unavailable (amber) gear sorts FIRST so a single-line overflow can only
    /// ever collapse an available piece into "N more" (#113 flag-don't-hide).
    static func gearCapsules(_ gear: [(name: String, available: Bool)]) -> [CardCapsule] {
        gear.sorted { lhs, rhs in
            (lhs.available ? 1 : 0, lhs.name) < (rhs.available ? 1 : 0, rhs.name)
        }.map { piece in
            CardCapsule(
                text: piece.name,
                tint: piece.available ? Theme.textSecondary : Theme.notes,
                fill: piece.available ? Theme.surfaceRaised : Theme.notes.opacity(0.14)
            )
        }
    }
}
