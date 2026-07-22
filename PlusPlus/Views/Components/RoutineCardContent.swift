import SwiftUI
import UIKit
import PlusPlusKit

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

    /// The rendered tag width, so `OverflowCapsuleRow` can predict the fit
    /// without a measurement pass. Mirrors `CardTagCapsule`'s font (the
    /// standard caption2, no longer monospaced) + horizontal padding;
    /// Dynamic-Type aware via the preferred font.
    func measuredWidth() -> CGFloat {
        let font = UIFont.preferredFont(forTextStyle: .caption2)
        var width = (text as NSString).size(withAttributes: [.font: font]).width
        if systemImage != nil {
            // The glyph is roughly square at the cap height, plus the HStack's
            // 3 pt spacing. An estimate is fine — only the leading schedule
            // capsule carries a glyph, and it always shows.
            width += font.pointSize * 1.2 + 3
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

// MARK: - Shared routine metadata (one producer, composable tiers)

/// The metadata every routine surface shows — the detail header, the library
/// card, the catalog card, and Today's pending card — from ONE producer, so a
/// routine reads the same facts the same way everywhere (2026-07-22, "facts,
/// then needs"). Each surface renders only the tiers it needs via
/// `RoutineMetaLine`/`ScheduleToken`/`RoutineEquipmentTags`; the chrome (card
/// background, Today's diff + Start, the detail heading) stays at each call
/// site — the same split as `ExerciseRowContent`/`EquipmentRowContent`.
struct RoutineMeta {
    var focus: String?
    var effort: String?
    var estimate: String?
    /// The schedule, when the surface shows one (cards + detail). Nil on Today
    /// — a card's presence on the timeline IS its schedule.
    var schedule: RoutineSchedule?
    var exercises: Int
    var sets: Int
    var restText: String
    /// Gear names paired with whether the active kit has each (amber-flag input).
    var gear: [(name: String, available: Bool)]

    /// From a live routine. `activeNames` is the active kit's membership;
    /// `includeSchedule` is false for Today's cards.
    init(routine: Routine, activeNames: Set<String>, includeSchedule: Bool = true) {
        let exercises = routine.sortedGroups.reduce(0) { $0 + $1.sortedExercises.count }
        self.exercises = exercises
        self.sets = routine.sortedGroups.reduce(0) { $0 + $1.sets * $1.sortedExercises.count }
        self.restText = Self.restLabel(routine.restSeconds)
        self.focus = exercises > 0 ? routine.focusLabel : nil
        self.effort = exercises > 0 ? routine.effortLabel : nil
        self.estimate = exercises > 0 ? routine.estimateText : nil
        self.schedule = includeSchedule ? routine.schedule : nil
        if routine.equipmentNames.isEmpty {
            self.gear = (exercises > 0 && !routine.isCardio) ? [(name: "Bodyweight", available: true)] : []
        } else {
            self.gear = routine.gearAvailability(activeNames: activeNames)
        }
    }

    /// From a catalog template: effort but no schedule, gear judged against
    /// the owned set. A template card shows no counts, so those stay zero.
    init(focus: String?, effort: String?, estimate: String?, gear: [(name: String, available: Bool)]) {
        self.focus = focus
        self.effort = effort
        self.estimate = estimate
        self.schedule = nil
        self.exercises = 0
        self.sets = 0
        self.restText = ""
        self.gear = gear
    }

    static func restLabel(_ seconds: Int) -> String {
        WorkoutMetric.duration.formatted(Double(seconds)) + (seconds < 60 ? "s" : "")
    }

    /// The cadence shown as plain text on a card ("anytime" when unscheduled).
    static func cadence(_ schedule: RoutineSchedule) -> String {
        schedule.normalized == .unscheduled ? "anytime" : schedule.shortLabel
    }

    /// The card's single identity + facts line: focus · schedule · effort · estimate.
    var cardLine: String {
        var parts: [String] = []
        if let focus { parts.append(focus) }
        if let schedule { parts.append(Self.cadence(schedule)) }
        if let effort { parts.append(effort) }
        if let estimate { parts.append(estimate) }
        return parts.joined(separator: " · ")
    }

    /// Today's pending card line: focus · estimate. No schedule (a card's
    /// presence on Today is its schedule) and no effort (the diff summary is
    /// the identity moment there, so the meta stays terse).
    var todayLine: String {
        [focus, estimate].compactMap { $0 }.joined(separator: " · ")
    }

    /// The detail's fact line (below the focus + schedule subtitle):
    /// estimate · N exercises · M sets · rest X.
    var factLine: String {
        var parts: [String] = []
        if let estimate { parts.append(estimate) }
        if exercises > 0 { parts.append("\(exercises) exercise\(exercises == 1 ? "" : "s")") }
        if sets > 0 { parts.append("\(sets) set\(sets == 1 ? "" : "s")") }
        if !restText.isEmpty { parts.append("rest \(restText)") }
        return parts.joined(separator: " · ")
    }
}

/// The schedule as a soft tag. In the detail it's a door (trailing chevron +
/// tap → the schedule tray); elsewhere it's a plain readout. Neutral fill: a
/// schedule is a setting, not a problem, so it never washes amber.
struct ScheduleToken: View {
    let schedule: RoutineSchedule
    var interactive: Bool = false
    var onTap: () -> Void = {}

    private var label: String {
        schedule.normalized == .unscheduled ? "Unscheduled" : schedule.shortLabel
    }

    var body: some View {
        if interactive {
            Button(action: onTap) { chip }
                .buttonStyle(.plain)
                .accessibilityLabel("Schedule: \(label)")
                .accessibilityHint("Opens the schedule")
                .accessibilityAddTraits(.isButton)
        } else {
            chip.accessibilityLabel("Schedule: \(label)")
        }
    }

    private var chip: some View {
        HStack(spacing: 3) {
            Image(systemName: "calendar")
            Text(label)
            if interactive {
                Image(systemName: "chevron.right")
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .font(.system(.caption2))
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
        .padding(.horizontal, CardTagCapsule.horizontalPadding)
        .padding(.vertical, 2.5)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: CardTagCapsule.cornerRadius))
    }
}

/// The equipment tier: amber-first soft tags (a piece missing from the active
/// kit washes amber). In the detail the amber tags are doors (trailing chevron
/// + tap → the resolve sheet) and the row wraps in full; on cards/Today they
/// only flag and collapse to "N more". `showLabel` prefixes a mono "Equipment".
struct RoutineEquipmentTags: View {
    let gear: [(name: String, available: Bool)]
    var interactive: Bool = false
    var showLabel: Bool = false
    var onEquipmentTap: (String) -> Void = { _ in }

    private var sortedGear: [(name: String, available: Bool)] {
        gear.sorted { (($0.available ? 1 : 0), $0.name) < (($1.available ? 1 : 0), $1.name) }
    }

    var body: some View {
        if gear.isEmpty {
            EmptyView()
        } else if interactive {
            VStack(alignment: .leading, spacing: 7) {
                if showLabel {
                    Text("EQUIPMENT")
                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                        .foregroundStyle(Theme.textFaint)
                }
                FlowLayout(spacing: 6) {
                    ForEach(sortedGear.indices, id: \.self) { index in
                        tag(sortedGear[index])
                    }
                }
            }
        } else {
            OverflowCapsuleRow(capsules: RoutineCardCapsules.gearCapsules(gear))
        }
    }

    @ViewBuilder
    private func tag(_ piece: (name: String, available: Bool)) -> some View {
        if piece.available {
            CardCapsule(text: piece.name).view()
        } else {
            Button { onEquipmentTap(piece.name) } label: {
                HStack(spacing: 3) {
                    Text(piece.name)
                    Image(systemName: "chevron.right")
                        .font(.system(.caption2, weight: .semibold))
                }
                .font(.system(.caption2))
                .foregroundStyle(Theme.notes)
                .lineLimit(1)
                .padding(.horizontal, CardTagCapsule.horizontalPadding)
                .padding(.vertical, 2.5)
                .background(Theme.notes.opacity(0.14), in: RoundedRectangle(cornerRadius: CardTagCapsule.cornerRadius))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(piece.name), not in your kit")
            .accessibilityHint("Opens ways to fix it")
            .accessibilityAddTraits(.isButton)
        }
    }
}

/// The shared card body: title + chevron, the one meta line, and the equipment
/// tier (inert on a card — the whole card is the tap target). Card chrome
/// (padding, background, the library's entrance flash, the catalog's `Button`)
/// stays at each call site.
struct RoutineCardContent: View {
    let title: String
    let meta: RoutineMeta

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
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
            if !meta.cardLine.isEmpty {
                Text(meta.cardLine)
                    .font(.system(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            if !meta.gear.isEmpty {
                RoutineEquipmentTags(gear: meta.gear)
            }
        }
    }
}

/// Builds the ordered gear capsules shared by every inert equipment row.
enum RoutineCardCapsules {
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
