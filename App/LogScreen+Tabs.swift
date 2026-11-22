import DesignSystem
import SwiftUI
import WorkoutStore

// Log's three tabs: History's count, calendar, and list; Diff's rows and rule; Balance's caption
// and groups. The period they read over is named once, in the bar (`LogScreen.periodText`).

extension LogScreen {
    /// History with nothing logged, under the empty calendar.
    static let noLoggedWorkoutsText = "Today is a good day to go from 0 to 1."
    static let goToWorkoutsLabel = "Go to Workouts"
    /// Under Diff's rows, or in their place while it has none.
    static let diffRuleText = "An exercise shows here once it has been done in two workouts."

    func historyTab(_ log: WorkoutLog) -> some View {
        let period = log.period(now: now, calendar: calendar)
        return VStack(alignment: .leading, spacing: 0) {
            loggedWorkoutCount(period)
                .padding(.bottom, Spacing.md)
            DayGrid(
                initials: LogPeriod.weekdayInitials(calendar: calendar),
                weeks: period.weeks.map { week in
                    week.map { day in
                        DayGrid.Square(
                            id: day.date,
                            number: LogPeriod.dayNumber(day, locale: locale, calendar: calendar),
                            isDone: day.hasLoggedWorkout,
                            isToday: day.isToday,
                            isShown: !day.isAfterToday,
                            spoken: LogPeriod.spokenDay(day, locale: locale, calendar: calendar),
                        )
                    }
                },
            )
            // A section break: the list, or the empty line and Go to Workouts, starts a part of
            // its own under the calendar.
            .padding(.bottom, Spacing.lg)
            if log.loggedWorkouts.isEmpty {
                noLoggedWorkouts
            } else {
                loggedWorkoutRows(log)
            }
        }
    }

    /// "9 workouts", its number in purple.
    private func loggedWorkoutCount(_ period: LogPeriod) -> some View {
        let text = period.loggedWorkoutCountText(locale: locale)
        let number = period.loggedWorkoutCount.formatted(.number.locale(locale))
        var attributed = AttributedString.monoNumbers(text, font: .ppRowDetailNumber)
        if let range = attributed.range(of: number) {
            attributed[range].foregroundColor = .pp(.done)
        }
        return Text(attributed)
            .font(.ppRowDetail)
            .foregroundStyle(.pp(.textSecondary))
    }

    private var noLoggedWorkouts: some View {
        VStack(spacing: Spacing.md) {
            Text(Self.noLoggedWorkoutsText)
                .font(.ppRowDetail)
                .foregroundStyle(.pp(.textSecondary))
                .multilineTextAlignment(.center)
            Button(Self.goToWorkoutsLabel, action: goToWorkouts)
                .buttonStyle(.pill)
                .accessibilityIdentifier("log.goToWorkouts")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Lazy, since History lists every finished workout there is. A row swiped left shows the
    /// system's red Delete, which asks first in a centered alert, "Delete <name>?", as a row on
    /// Workouts does (`LogScreen.delete(_:)`).
    private func loggedWorkoutRows(_ log: WorkoutLog) -> some View {
        let shown = log.loggedWorkouts.filter { !leaving.contains($0.id) }
        // The system draws a swiped action inset from its row's end, so the row it swipes runs
        // past History's margin to that inset short of the screen's edge, and Delete ends in
        // line with the line under the row, as on Workouts.
        let overhang = Spacing.md - WorkoutsScreen.swipeInset
        return LazyVStack(alignment: .leading, spacing: 0) { ForEach(shown) { loggedWorkout in
            let name = Self.name(of: loggedWorkout)
            let spoken = loggedWorkout.spokenLogLine(locale: locale, calendar: calendar)
            Button {
                openLoggedWorkout(loggedWorkout.id)
            } label: {
                LogRow(
                    name,
                    detail: loggedWorkout.logLine(locale: locale, calendar: calendar),
                    spoken: "\(name), \(spoken)",
                )
                .overlay(alignment: .bottom) { RowLine() }
                .padding(.trailing, overhang)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("log.workout")
            .swipeActions(edge: .trailing) {
                Button("Delete", role: .destructive) { askToDelete(loggedWorkout) }
            }
            .padding(.trailing, -overhang)
        } }
    }

    func diffTab(_ log: WorkoutLog) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(log.diff(in: session.exercises, now: now, calendar: calendar)) { item in
                diffRow(item)
            }
            Text(Self.diffRuleText)
                .font(.ppRowDetail)
                .foregroundStyle(.pp(.textSecondary))
                .padding(.top, Spacing.md)
        }
    }

    private func diffRow(_ item: DiffItem) -> some View {
        let load = item.exercise?.load
        let first = item.first.figure(load: load, locale: locale)
        let latest = item.latest.figure(load: load, locale: locale)
        return LogRow(
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

    @ViewBuilder
    func balanceTab(_ log: WorkoutLog) -> some View {
        let balance = log.balance(in: session.exercises, now: now, calendar: calendar)
        let most = balance.mostSets
        VStack(alignment: .leading, spacing: 0) {
            Text("Sets")
                .font(.ppRowDetail)
                .foregroundStyle(.pp(.textSecondary))
                .padding(.bottom, Spacing.md)
            // No line between the groups: their bars part them, a section's room apart.
            VStack(alignment: .leading, spacing: Spacing.lg) {
                ForEach(balance.groups) { group in
                    CountRow(
                        group.group.name,
                        count: group.sets.formatted(.number.locale(locale)),
                        fraction: most > 0 ? Double(group.sets) / Double(most) : 0,
                        isStressed: group.isMissed,
                        spoken: group.spokenText(locale: locale),
                    )
                }
            }
        }
    }

    /// A logged workout's name as it was, New workout for an empty one.
    static func name(of loggedWorkout: LoggedWorkout) -> String {
        loggedWorkout.workoutName.isEmpty ? WorkoutScreen.defaultName : loggedWorkout.workoutName
    }

    /// A gain in green; anything else in gray; nothing for a change of measure.
    static func tag(_ change: Change, locale: Locale) -> LogTag? {
        guard let text = change.text(locale: locale) else { return nil }
        return change.isUp ? .gain(text) : .quiet(text)
    }
}
