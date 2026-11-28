import DesignSystem
import Session
import SwiftUI
import WorkoutStore

/// The record of finished workouts, read three ways in the system's segmented control under the
/// bar: History, a calendar of the period and the workouts themselves, newest first; Diff, what
/// changed since the period's first day; and Balance, each muscle group's sets. "Log" is the
/// bar's own inline title, centered, with ++ leading and the period trailing, once for all
/// three tabs: "Oct 25 – Nov 21", plain secondary text, not a control.
/// It opens on History each time the drawer shows it, and after a finish, which goes there
/// through the drawer: the workout just finished comes into History once the drawer has closed
/// (`bringIn()`). The period is `LogPeriod`'s four calendar weeks. Once a workout has been
/// finished, whenever Apple Health reads as never asked and Log holds a finished workout,
/// History opens on a green button to sync workouts there (`healthPromptSlot`), until its ×
/// dismisses it for good.
/// Purple marks every logged number and green only a gain; nothing else on it is green. A
/// workout session's row pushes it, read-only, with the system push, as a saved workout is
/// pushed on Workouts, and swiped left offers Delete, as a saved workout's row does there.
struct LogScreen: View {
    @Bindable var session: AppSession

    enum Tab: Hashable, CaseIterable {
        case history
        case diff
        case balance

        var title: String {
            switch self {
            case .history: "History"
            case .diff: "Diff"
            case .balance: "Balance"
            }
        }
    }

    /// View state: it starts on History each time Log opens from the drawer, and holds across a
    /// push and pop, since the stack keeps its root.
    @State var tab = Tab.history
    /// The workout session Delete last asked about, kept as the alert goes, so its line keeps the
    /// name and day.
    @State var deleting: WorkoutSession?
    @State var isAskingToDelete = false
    /// Workout sessions whose delete is confirmed, left out of History from the confirming tap,
    /// before the store has taken the delete.
    @State var leaving: Set<WorkoutSession.ID> = []
    /// The workout just finished, left out of History until it comes in, a moment after the
    /// drawer has closed over Log (`bringIn()`). Held here, not on the session, so it goes with
    /// the screen and no path can leave the workout missing from History.
    @State var arriving: WorkoutSession.ID?
    /// History's empty line and Go to Workouts fading out ahead of the first workout ever, which
    /// comes in only once they have gone, so its text never shows over theirs.
    @State var emptyGivesWay = false
    /// With Reduce Motion, the workout just finished, in History at its place but not yet faded
    /// in: the rows take their new places at once, and only this one fades (`fadesIn(_:)`).
    @State var fadingIn: WorkoutSession.ID?
    /// The scroll view's height inside its bars, for the empty History to fill.
    @State private var visibleHeight: CGFloat = 0
    @Environment(\.locale) var locale
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    /// How long after the drawer has closed over Log a workout just finished comes into History.
    static let arrivalDelay = Duration.milliseconds(330)
    /// How long History's empty line and Go to Workouts take to fade out, from the drawer having
    /// closed, ahead of the first workout ever: within `arrivalDelay`, so that row comes in on
    /// the same beat as any other.
    static let emptyFade = Duration.milliseconds(250)

    /// Seeded from the session, so the first frame already leaves a workout just finished out.
    init(session: AppSession) {
        self.session = session
        _arriving = State(initialValue: session.justFinished)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Picker("Show", selection: $tab) {
                        ForEach(Tab.allCases, id: \.self) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, Spacing.lg)
                    if let log = session.log {
                        tabContent(log)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xl)
                // With nothing logged, History's line and Go to Workouts center in the room
                // under the calendar; where they need more, at the largest sizes, it scrolls.
                .frame(minHeight: isHistoryEmpty ? visibleHeight : nil, alignment: .top)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.containerSize.height - geometry.contentInsets.top
                    - geometry.contentInsets.bottom
            } action: { _, height in
                visibleHeight = height
            }
            // One History row open at a time, closed by a scroll or a tap anywhere else.
            .swipeActionsContainer()
            .accessibilityHidden(session.isDrawerOpen)
            .background { Color.pp(.background).ignoresSafeArea() }
            .navigationDestination(item: pushedWorkoutSession) { id in
                if let log = session.log, let workoutSession = log.workoutSession(id: id) {
                    WorkoutSessionScreen(
                        workoutSession: workoutSession,
                        log: log,
                        exercises: session.exercises,
                    )
                }
            }
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MenuButton(session: session)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    periodText
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        // Outside the stack, as Workouts': centered, with the system's colors.
        // "Delete <name>?", Workouts' words, read here as deleting the workout itself: the title
        // names Log, and the line under it the one time through.
        .alert(
            "Delete from Log?",
            isPresented: $isAskingToDelete,
            presenting: deleting,
        ) { workoutSession in
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { delete(workoutSession.id) }
        } message: { workoutSession in
            let day = workoutSession.dayText(locale: locale, calendar: calendar)
            Text("\(Self.name(of: workoutSession)), \(day)")
        }
        .task { await bringIn() }
    }

    /// Reads the log, and brings a workout just finished into History once the drawer has
    /// closed and `arrivalDelay` has passed: its row opens to its height as it fades in, the rows
    /// under it moving down, the count and today's square following. Log always shows with the
    /// drawer already told to close, so its arrival counts from here.
    ///
    /// The first workout ever finds History empty: its empty line and Go to Workouts fade out
    /// first, from the drawer having closed (`emptyFade`), and the row comes in once they have
    /// gone, where History's first row goes. Crossfaded together, the row's text showed over
    /// theirs for about a quarter second.
    private func bringIn() async {
        let start = ContinuousClock.now
        session.takeJustFinished()
        await session.refreshLog()
        guard let coming = arriving else { return }
        let closed = start + DrawerWay.arrival(reduceMotion: reduceMotion)
        var due = closed + Self.arrivalDelay
        // Only for a row that will come in: with a log read missing it, the empty part stays.
        if showsNoWorkoutSessions, session.log?.workoutSession(id: coming) != nil {
            guard await (try? beat(until: closed)) != nil else { return }
            withAnimation(.easeOut(duration: Self.emptyFade / .seconds(1))) {
                emptyGivesWay = true
            }
            // A slow read of the log: the row still waits for the fade to end.
            due = max(due, .now + Self.emptyFade)
        }
        guard await (try? beat(until: due)) != nil else { return }
        withAnimation(.snappy) {
            if reduceMotion {
                fadingIn = coming
            }
            arriving = nil
            emptyGivesWay = false
        }
    }

    func askToDelete(_ workoutSession: WorkoutSession) {
        deleting = workoutSession
        isAskingToDelete = true
    }

    /// Takes the row out at once, the rows below closing the gap, then deletes the workout
    /// session; the log read after it moves the count, the calendar, Diff, and Balance.
    private func delete(_ id: WorkoutSession.ID) {
        withAnimation(.snappy) {
            _ = leaving.insert(id)
        }
        Task {
            await session.deleteWorkoutSession(id)
            // Gone from the log once stored; back in History if the delete failed.
            withAnimation(.snappy) {
                _ = leaving.remove(id)
            }
        }
    }

    /// The period, trailing in the bar. Always there, empty until the log is read, so the bar
    /// never puts the item in or takes it out. Its numbers are set in SF Mono, but the bar draws
    /// a system font's monospaced design in the default one, in a run, a text of its own, or a
    /// `UIFont`, so they show in SF Pro; only a named font kept its face.
    private var periodText: some View {
        let period = session.log?.period(now: now, calendar: calendar)
        let text = period?.rangeText(locale: locale, calendar: calendar) ?? ""
        return Text(AttributedString.monoNumbers(text, font: .ppRowDetailNumber))
            .font(.ppRowDetail)
            .foregroundStyle(.pp(.textSecondary))
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel(period?.spokenRange(locale: locale, calendar: calendar) ?? "")
            .accessibilityShown(period != nil)
            .hiddenBehindDrawer()
    }

    @ViewBuilder
    private func tabContent(_ log: WorkoutLog) -> some View {
        switch tab {
        case .history: historyTab(log.leavingOut(arriving))
        case .diff: diffTab(log)
        case .balance: balanceTab(log)
        }
    }

    private var isHistoryEmpty: Bool {
        tab == .history && showsNoWorkoutSessions
    }

    /// Whether History lists nothing, the workout yet to come in left out.
    private var showsNoWorkoutSessions: Bool {
        session.log?.leavingOut(arriving).workoutSessions.isEmpty == true
    }

    /// The pushed workout session, which the back button and the back swipe pop.
    private var pushedWorkoutSession: Binding<WorkoutSession.ID?> {
        Binding {
            if case let .workoutSession(id) = session.screen {
                id
            } else {
                nil
            }
        } set: { id in
            if let id {
                session.openWorkoutSession(id)
            } else {
                session.popWorkoutSession()
            }
        }
    }

    func openWorkoutSession(_ id: WorkoutSession.ID) {
        session.openWorkoutSession(id)
    }

    /// Workouts at the root, never pushed onto Log, by way of the drawer: a quick version of
    /// opening it and tapping Workouts (`AppSession.show(_:after:throughDrawer:markWait:)`): it
    /// opens at the ++ button's pace, holds a moment, its mark slides from Log to Workouts, it
    /// holds again, and it closes over Workouts (`DrawerWay`). With VoiceOver it goes straight
    /// there: a drawer passing by unasked reads as noise.
    func goToWorkouts() {
        guard !voiceOver else {
            session.showWorkouts()
            return
        }
        session.showThroughDrawer(.workouts, reduceMotion: reduceMotion)
    }

    var now: Date {
        .now
    }

    var calendar: Calendar {
        .current
    }
}

#Preview {
    LogScreen(
        session: AppSession(
            workout: Workout(name: "Upper body"),
            store: nil,
            namer: .muscleGroupsOnly,
        ),
    )
}
