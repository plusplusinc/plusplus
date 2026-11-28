import DesignSystem
import Session
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
        let healthPrompt = session.healthPrompt
        let showsHealthPrompt = healthPrompt != nil
        return VStack(alignment: .leading, spacing: 0) {
            if let healthPrompt {
                healthPromptSlot(healthPrompt)
                    .padding(.bottom, Spacing.lg)
                    .transition(
                        reduceMotion
                            ? AnyTransition.cardCrossfade
                            : AnyTransition(.cutAway),
                    )
            }
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
            // The rows are always there, the empty part under their place while they are none:
            // the first workout ever comes in where History's first row goes, as any other
            // does, and never rides up from where the empty part sat. Stacked, not laid over
            // the rows in a ZStack: there, at the largest text sizes, Go to Workouts' label
            // was cut short on one line rather than wrapping.
            loggedWorkoutRows(log)
            if log.loggedWorkouts.isEmpty {
                noLoggedWorkouts
                    .opacity(emptyGivesWay ? 0 : 1)
                    .allowsHitTesting(!emptyGivesWay)
                    .accessibilityHidden(emptyGivesWay)
                    // Gone at once once faded: its fade is `emptyGivesWay`'s.
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
        }
        // The card's room closes as it fades, cut off where the calendar and rows have risen
        // to (`CutAway`). With Reduce Motion nothing rises: the card fades with its room kept,
        // then the room closes in one step (`afterCardCrossfade`); coming in, the room opens
        // at once and the card fades in over it.
        .animation(healthOfferAnimation(showing: showsHealthPrompt), value: showsHealthPrompt)
    }

    private func healthOfferAnimation(showing: Bool) -> Animation? {
        guard reduceMotion else { return .snappy }
        return showing ? nil : .afterCardCrossfade
    }

    /// The ask to sync to Apple Health, first in History above the count, once a workout has
    /// been finished, whenever Health reads as never asked and Log holds a finished workout,
    /// until its × dismisses it for good (`AppSession.healthPrompt`). "Sync to Apple Health" is
    /// the session's one ask (`AppSession.syncFromPrompt()`): Apple's sheet, then every workout
    /// in Log sent once it allows, and the prompt goes as the answer is read; answered Don't
    /// Allow, a note says the Health app can turn it on. The × leaves a note that Settings can.
    /// The row gives way to a note in place (`promptSwap(isNote:reduceMotion:)`); the note goes
    /// on its OK, its fill run out, or Log left, by the leave the row takes after Allow. It is
    /// in Log's first frame after a finish, the access read since launch, so it doesn't come in
    /// over the workout arriving; only a read landing while Log is open, as with Log opened
    /// moments after a launch, brings it in, on its leave run backward.
    private func healthPromptSlot(_ prompt: HealthPrompt) -> some View {
        let health = session.health
        return ZStack {
            switch prompt {
            case .ask:
                PromptRow(
                    "Sync to Apple Health",
                    take: { Task { await session.syncFromPrompt() } },
                    dismiss: { health.declineOffer() },
                )
                .promptSwap(isNote: false, reduceMotion: reduceMotion)
            case let .note(note):
                PromptNote(Self.healthNoteText(note), end: { health.endNote() })
                    .id(note)
                    .onDisappear { health.endNote() }
                    .promptSwap(isNote: true, reduceMotion: reduceMotion)
            }
        }
        .animation(reduceMotion ? .cardCrossfade : .snappy, value: prompt)
    }

    static func healthNoteText(_ note: HealthSaving.Note) -> String {
        switch note {
        // The app's own Settings, named so it isn't read as the phone's, which has no entry
        // for this; its stops joined by no-break spaces so no line ends on the arrow.
        case .dismissed:
            "You can enable sync later in PlusPlus\u{A0}Settings\u{A0}›\u{A0}Apple\u{A0}Health."
        case .denied: "You can enable sync later in Apple\u{A0}Health."
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
    /// system's red Delete, which asks first in a centered alert, "Delete from Log?" over the
    /// name and day (`LogScreen.delete(_:)`).
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
            .opacity(loggedWorkout.id == fadingIn ? 0 : 1)
            .onAppear { fadesIn(loggedWorkout.id) }
        } }
        // With Reduce Motion a workout coming in moves nothing: the rows take their places at
        // once, and the new one fades in from its own.
        .transaction(value: arriving) {
            if reduceMotion {
                $0.animation = nil
            }
        }
    }

    /// Fades in the workout just finished, with Reduce Motion, once its row is in place.
    private func fadesIn(_ id: LoggedWorkout.ID) {
        guard id == fadingIn else { return }
        withAnimation(.snappy) { fadingIn = nil }
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
