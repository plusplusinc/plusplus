import SwiftUI
import SwiftData
import PlusPlusKit

/// The routine's schedule, in a dedicated tray (2026-07-22). It used to be a
/// section inside routine settings; now it opens from the detail header's
/// tappable schedule chip AND a "Schedule" row in settings, so scheduling is
/// one place reachable two ways. Three modes — Off / Days of the week / Every
/// few days — and, for the weekday mode, a "sharing a day" list that names
/// what ELSE is on each picked day (the old design hid that behind a 4 pt dot
/// and a cryptic legend). Every edit writes `routine.schedule` live; there are
/// no new persisted fields.
///
/// The editor body lives in `ScheduleEditor` (2026-07-24) so it can also be
/// the second stage of Today's two-step "Schedule a routine" tray; this stays
/// the standalone sheet wrapper (header + detents) for its two direct callers
/// (`RoutineDetailView`, `RoutineSettingsScreen`).
struct ScheduleTray: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var routine: Routine

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Schedule", closeOnly: true) { dismiss() }
                .padding(.horizontal, 18)

            ScheduleEditor(routine: routine)

            Spacer(minLength: 0)
        }
        .presentationBackground(Theme.background)
        .presentationDetents([.medium, .large])
    }
}

/// The schedule editor proper: mode picker + day chips / frequency steppers +
/// captions, writing `routine.schedule` live. Carries NO header or
/// presentation chrome so it can be embedded (the standalone `ScheduleTray`
/// wraps it with a `SheetHeader` + detents; Today's `ScheduleRoutineTray`
/// wraps it as a slide stage with a back key).
struct ScheduleEditor: View {
    @Bindable var routine: Routine
    /// Other routines' schedules feed the occupancy dots + the sharing list.
    @Query(sort: \Routine.order) private var allRoutines: [Routine]

    @State private var scheduleMode: Int
    @State private var scheduleDays: Set<Int>
    @State private var scheduleTimes: Int
    @State private var schedulePerDays: Int
    /// The schedule (and its anchor stamp) as the editor opened. Live
    /// per-interaction persistence means an EXPLORATORY round trip —
    /// peek at the other mode, toggle a day off and back on — writes
    /// interim values that each stamp `scheduleChangedAt`; when the
    /// value lands back where it started, the entry stamp is restored
    /// so a net no-op editing session can't move the due-ness anchor
    /// and quietly clear a carried day (swift-reviewer, round 2b).
    private let entrySchedule: RoutineSchedule
    private let entryStamp: Date?

    init(routine: Routine) {
        self.routine = routine
        entrySchedule = routine.schedule
        entryStamp = routine.scheduleChangedAt
        // Seed the editor from the stored schedule; edits write back through
        // persistSchedule() on every change.
        switch routine.schedule {
        case .unscheduled:
            _scheduleMode = State(initialValue: 0)
            _scheduleDays = State(initialValue: [])
            _scheduleTimes = State(initialValue: 3)
            _schedulePerDays = State(initialValue: 7)
        case .weekdays(let days):
            _scheduleMode = State(initialValue: 1)
            _scheduleDays = State(initialValue: days)
            _scheduleTimes = State(initialValue: 3)
            _schedulePerDays = State(initialValue: 7)
        case .frequency(let times, let perDays):
            _scheduleMode = State(initialValue: 2)
            _scheduleDays = State(initialValue: [])
            _scheduleTimes = State(initialValue: times)
            _schedulePerDays = State(initialValue: perDays)
        }
    }

    var body: some View {
        // Self-contained NavigationStack so the schedule-mode push row works in
        // BOTH embed contexts (the standalone ScheduleTray sheet and Today's
        // slide-stage ScheduleRoutineTray, neither of which supplies one); the
        // root nav bar is hidden so the host's header stays the header and only
        // the pushed selection screen shows a (system) back bar.
        NavigationStack {
          ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                NavigationSelectRow(
                    title: "Schedule",
                    selection: $scheduleMode,
                    options: [
                        .init(value: 0, label: "Off"),
                        .init(value: 1, label: "Days of the week"),
                        .init(value: 2, label: "Every few days"),
                    ],
                    identifier: "scheduleModeRow"
                )
                .padding(.top, 12)
                .onChange(of: scheduleMode) { _, _ in persistSchedule() }

                if scheduleMode == 1 {
                    dayChips
                        .padding(.top, 18)
                    sharingSection
                } else if scheduleMode == 2 {
                    frequencySteppers
                        .padding(.top, 16)
                }

                if let caption = scheduleCaption {
                    Text(caption)
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.top, 16)
                }

                // "Every few days" anchors to your last completion — a
                // load-bearing distinction every time the mode is chosen.
                if scheduleMode == 2 {
                    Text("It counts from your last completion, not the calendar week. Miss a day and nothing stacks up.")
                        .font(.system(.caption))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
          }
          .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Weekday circles

    /// Fixed Sunday-first labels matching Calendar weekday numbers 1…7.
    private static let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]
    /// Monday-first calendar weekday numbers.
    private static let mondayFirstWeekdays = [2, 3, 4, 5, 6, 7, 1]
    /// Short names for the sharing list, Sunday-indexed (weekday - 1).
    private static let shortDayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private var dayChips: some View {
        HStack(spacing: 4) {
            ForEach(Self.mondayFirstWeekdays, id: \.self) { weekday in
                let selected = scheduleDays.contains(weekday)
                VStack(spacing: 5) {
                    Button {
                        if selected {
                            scheduleDays.remove(weekday)
                        } else {
                            scheduleDays.insert(weekday)
                        }
                        persistSchedule()
                    } label: {
                        // Solid selection blue (#210), not green: scheduling a
                        // day is choosing an option; the due OUTPUT on Today
                        // stays green.
                        Text(Self.dayLabels[weekday - 1])
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                            .foregroundStyle(selected ? Theme.onSelected : Theme.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(
                                selected ? AnyShapeStyle(Theme.selected) : AnyShapeStyle(Theme.background),
                                in: Circle()
                            )
                            .overlay(Circle().strokeBorder(selected ? Color.clear : Theme.border, lineWidth: 1))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("scheduleDay\(weekday)")

                    // A dot marks a day another routine already sits on.
                    Circle()
                        .fill(occupiedDays[weekday] != nil ? Theme.textFaint : Color.clear)
                        .frame(width: 4, height: 4)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .animation(Theme.Anim.selection, value: scheduleDays)
        .sensoryFeedback(.selection, trigger: scheduleDays)
    }

    // MARK: - Collisions ("sharing a day")

    /// weekday → the OTHER routines scheduled on it (first-seen order). Only
    /// `.weekdays` schedules occupy a fixed day; a floating pace doesn't.
    private var occupiedDays: [Int: [String]] {
        var result: [Int: [String]] = [:]
        for other in allRoutines where other !== routine {
            if case .weekdays(let days) = other.schedule.normalized {
                for day in days { result[day, default: []].append(other.name) }
            }
        }
        return result
    }

    /// Each picked day that another routine also lives on, named. Replaces the
    /// old "· = X lives on wed" legend — the collision names itself here.
    @ViewBuilder
    private var sharingSection: some View {
        let shared = Self.mondayFirstWeekdays.filter { scheduleDays.contains($0) && occupiedDays[$0] != nil }
        if !shared.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SheetSectionLabel("SHARING A DAY")
                    .padding(.top, 22)
                ForEach(shared, id: \.self) { weekday in
                    HStack(spacing: 12) {
                        Text(Self.shortDayNames[weekday - 1])
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 34, alignment: .leading)
                        Text((occupiedDays[weekday] ?? []).joined(separator: ", "))
                            .font(.system(.caption))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 5)
                }
            }
        }
    }

    // MARK: - Frequency

    private var frequencySteppers: some View {
        VStack(spacing: 0) {
            MetricStepperRow(
                label: "Sessions",
                value: "\(scheduleTimes)×",
                identifier: "scheduleTimes",
                onDecrement: { scheduleTimes = max(1, scheduleTimes - 1); persistSchedule() },
                onIncrement: { scheduleTimes = min(14, scheduleTimes + 1); persistSchedule() }
            )
            MetricStepperRow(
                label: "Every",
                value: "\(schedulePerDays) days",
                identifier: "schedulePerDays",
                onDecrement: { schedulePerDays = max(1, schedulePerDays - 1); persistSchedule() },
                onIncrement: { schedulePerDays = min(30, schedulePerDays + 1); persistSchedule() }
            )
        }
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }

    // MARK: - Captions + persistence

    private var scheduleCaption: String? {
        switch scheduleMode {
        case 1:
            return scheduleDays.isEmpty
                ? "No days picked yet, so this stays unscheduled."
                : "On the marked days. A missed day carries over until you do it."
        case 2:
            let interval = (schedulePerDays + scheduleTimes - 1) / scheduleTimes
            return "\(scheduleTimes)×/\(schedulePerDays)d comes around about every \(interval) day\(interval == 1 ? "" : "s")."
        default:
            return "No schedule. This routine never appears on Today by itself. Swap it in whenever."
        }
    }

    private func persistSchedule() {
        switch scheduleMode {
        case 1: routine.schedule = .weekdays(scheduleDays)
        case 2: routine.schedule = .frequency(times: scheduleTimes, perDays: schedulePerDays)
        default: routine.schedule = .unscheduled
        }
        // Back to where the editor opened → this session nets no change;
        // restore the entry stamp (see entrySchedule).
        if routine.schedule == entrySchedule {
            routine.scheduleChangedAt = entryStamp
        }
    }
}
