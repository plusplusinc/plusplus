import DesignSystem
import SwiftUI
import WorkoutStore

// Log's three lists, and the one line each shows with nothing in it.

extension LogScreen {
    /// The one line the tab showing has in place of its rows; nil while it has rows, and before
    /// the first read, so the line never flashes before the workouts come.
    var emptyText: String? {
        guard let log = session.log else { return nil }
        if log.workouts.isEmpty {
            return tab == .progress
                ? "Nothing here yet. Do an exercise in two workouts."
                : "Nothing here yet. Finish a workout."
        }
        switch tab {
        case .workouts:
            return nil
        case .progress:
            return progress(log).isEmpty ? "Nothing here yet. Do an exercise in two workouts." : nil
        case .gaps:
            return gaps(log).isEmpty ? "Nothing here. No gaps in the last 4 weeks." : nil
        }
    }

    func workoutRows(_ log: WorkoutLog) -> some View {
        ForEach(log.workouts) { workout in
            let name = Self.name(of: workout)
            Button {
                openWorkout(workout.id)
            } label: {
                LogRow(
                    name,
                    detail: workout.logLine(locale: locale, calendar: calendar),
                    spoken: "\(name), \(workout.spokenLogLine(locale: locale, calendar: calendar))",
                )
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("log.workout")
            .overlay(alignment: .bottom) { RowLine() }
        }
    }

    func progressRows(_ log: WorkoutLog) -> some View {
        ForEach(progress(log)) { item in
            let load = item.exercise?.load
            let first = item.first.figure(load: load, locale: locale)
            let latest = item.latest.figure(load: load, locale: locale)
            LogRow(
                item.name,
                tag: Self.tag(item.change, locale: locale),
                figures: "\(first) → \(latest)",
                detail: item.isPerSide ? "Per side." : nil,
                spoken: [
                    item.name,
                    item.change.spokenText(locale: locale),
                    "from \(item.first.spokenFigure(load: load, locale: locale))"
                        + " to \(item.latest.spokenFigure(load: load, locale: locale))",
                ].compactMap(\.self).joined(separator: ", "),
            )
            .overlay(alignment: .bottom) { RowLine() }
        }
    }

    @ViewBuilder
    func gapRows(_ log: WorkoutLog) -> some View {
        let gaps = gaps(log)
        if !gaps.notWorkedLately.isEmpty {
            heading("Not worked lately")
            ForEach(gaps.notWorkedLately) { group in
                LogRow(
                    group.group.name,
                    tag: .quiet(group.text(locale: locale)),
                    spoken: "\(group.group.name), \(group.text(locale: locale))",
                )
                .overlay(alignment: .bottom) { RowLine() }
            }
        }
        if !gaps.notMoving.isEmpty {
            heading("Not moving")
            ForEach(gaps.notMoving) { stuck in
                let load = stuck.exercise?.load
                LogRow(
                    stuck.name,
                    tag: .quiet(stuck.countText(locale: locale)),
                    figures: stuck.topSet.figure(load: load, locale: locale),
                    detail: stuck.isPerSide ? "Per side." : nil,
                    spoken: "\(stuck.name), "
                        + stuck.topSet.spokenFigure(load: load, locale: locale)
                        + " in \(stuck.countText(locale: locale))",
                )
                .overlay(alignment: .bottom) { RowLine() }
            }
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.ppRowDetail.weight(.semibold))
            .foregroundStyle(.pp(.textSecondary))
            .accessibilityAddTraits(.isHeader)
            .padding(.top, Spacing.lg)
    }

    private func progress(_ log: WorkoutLog) -> [ProgressItem] {
        log.progress(in: session.exercises, now: now, calendar: calendar)
    }

    private func gaps(_ log: WorkoutLog) -> Gaps {
        log.gaps(in: session.exercises, now: now, calendar: calendar)
    }

    /// A workout's name as it was, New routine for an empty one.
    static func name(of workout: Workout) -> String {
        workout.routineName.isEmpty ? RoutineScreen.defaultName : workout.routineName
    }

    /// A gain in green; anything else in gray; nothing for a change of measure.
    static func tag(_ change: Change, locale: Locale) -> LogTag? {
        guard let text = change.text(locale: locale) else { return nil }
        return change.isUp ? .gain(text) : .quiet(text)
    }
}
