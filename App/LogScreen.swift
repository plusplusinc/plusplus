import DesignSystem
import Session
import SwiftUI
import WorkoutStore

/// The record of finished workouts, read three ways in the system's segmented control under the
/// bar: History, a calendar of the period and the workouts themselves, newest first; Diff, what
/// changed since the period's first day; and Balance, each muscle group's sets. "Log" is the
/// bar's own inline title, centered, with ++ leading and the period trailing, once for all
/// three tabs: "Oct 25 – Nov 21", plain secondary text, not a control.
/// It opens on History each time the drawer shows it. The period is `LogPeriod`'s four
/// calendar weeks.
/// Purple marks every logged number and green only a gain; nothing else on it is green. A
/// logged workout's row pushes it, read-only, with the system push, as a saved workout is
/// pushed on Workouts.
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
    /// The scroll view's height inside its bars, for the empty History to fill.
    @State private var visibleHeight: CGFloat = 0
    @Environment(\.locale) var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

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
            .accessibilityHidden(session.isDrawerOpen)
            .background { Color.pp(.background).ignoresSafeArea() }
            .navigationDestination(item: pushedLoggedWorkout) { id in
                if let log = session.log, let loggedWorkout = log.loggedWorkout(id: id) {
                    LoggedWorkoutScreen(
                        loggedWorkout: loggedWorkout,
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
        .task { await session.refreshLog() }
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
        case .history: historyTab(log)
        case .diff: diffTab(log)
        case .balance: balanceTab(log)
        }
    }

    private var isHistoryEmpty: Bool {
        tab == .history && session.log?.loggedWorkouts.isEmpty == true
    }

    /// The pushed logged workout, which the back button and the back swipe pop.
    private var pushedLoggedWorkout: Binding<LoggedWorkout.ID?> {
        Binding {
            if case let .loggedWorkout(id) = session.screen {
                id
            } else {
                nil
            }
        } set: { id in
            if let id {
                session.openLoggedWorkout(id)
            } else {
                session.popLoggedWorkout()
            }
        }
    }

    func openLoggedWorkout(_ id: LoggedWorkout.ID) {
        session.openLoggedWorkout(id)
    }

    /// Workouts at the root, never pushed onto Log, by way of the drawer: a quick version of
    /// opening it and tapping Workouts (`AppSession.show(_:throughDrawer:markWait:)`): it opens
    /// at the ++ button's pace, holds a moment, its mark slides from Log to Workouts, it holds
    /// again, and it closes over Workouts (`DrawerWay`). With VoiceOver it goes straight there:
    /// a drawer passing by unasked reads as noise.
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
