import DesignSystem
import SwiftUI
import WorkoutStore

// Log's three tabs: History's period line, calendar, and list; Diff's date line, rows, and rule;
// Gaps' caption and groups.

extension LogScreen {
    /// History with nothing logged, under the empty calendar.
    static let noLoggedWorkoutsText = "Today is a good day to go from 0 to 1."
    static let goToWorkoutsLabel = "Go to Workouts"
    /// Under Diff's rows, or in their place while it has none.
    static let diffRuleText = "An exercise shows here once it has been done in two workouts."

    func historyTab(_ log: WorkoutLog) -> some View {
        let period = log.period(now: now, calendar: calendar)
        // At the accessibility sizes the count goes under the line, as a row's tag does.
        let top = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xxs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.sm))
        return VStack(alignment: .leading, spacing: 0) {
            top {
                periodLine("Since \(period.firstDayText(locale: locale, calendar: calendar))")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(
                        "Since \(period.spokenFirstDay(locale: locale, calendar: calendar))",
                    )
                loggedWorkoutCount(period)
                    .layoutPriority(1)
            }
            .accessibilityElement(children: .combine)
            .padding(.bottom, Spacing.md)
            DayGrid(
                initials: LogPeriod.weekdayInitials(calendar: calendar),
                weeks: period.weeks.map { week in
                    week.map { day in
                        DayGrid.Square(
                            id: day.date,
                            isDone: day.hasLoggedWorkout,
                            isToday: day.isToday,
                            isShown: !day.isAfterToday,
                            spoken: LogPeriod.spokenDay(day, locale: locale, calendar: calendar),
                        )
                    }
                },
            )
            .padding(.bottom, Spacing.md)
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

    /// Lazy, since History lists every finished workout there is.
    private func loggedWorkoutRows(_ log: WorkoutLog) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) { ForEach(log.loggedWorkouts) { loggedWorkout in
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
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("log.workout")
            .overlay(alignment: .bottom) { RowLine() }
        } }
    }

    func diffTab(_ log: WorkoutLog) -> some View {
        let period = log.period(now: now, calendar: calendar)
        return VStack(alignment: .leading, spacing: 0) {
            periodLine("\(period.firstDayText(locale: locale, calendar: calendar)) → today")
                .accessibilityLabel(
                    "\(period.spokenFirstDay(locale: locale, calendar: calendar)) to today",
                )
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
    func gapsTab(_ log: WorkoutLog) -> some View {
        let period = log.period(now: now, calendar: calendar)
        let gaps = log.gaps(in: session.exercises, now: now, calendar: calendar)
        let most = gaps.mostSets
        VStack(alignment: .leading, spacing: 0) {
            periodLine("Sets since \(period.firstDayText(locale: locale, calendar: calendar))")
                .accessibilityLabel(
                    "Sets since \(period.spokenFirstDay(locale: locale, calendar: calendar))",
                )
                .padding(.bottom, Spacing.sm)
            // No line between the groups: their bars part them.
            ForEach(gaps.groups) { group in
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

    /// A tab's first line, naming the period's first day, its numbers in SF Mono.
    private func periodLine(_ text: String) -> some View {
        Text(AttributedString.monoNumbers(text, font: .ppRowDetailNumber))
            .font(.ppRowDetail)
            .foregroundStyle(.pp(.textSecondary))
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
