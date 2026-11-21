import DesignSystem
import Session
import SwiftUI
import WorkoutStore

/// The record of finished workouts, read three ways in the system's segmented control under the
/// bar: History, a calendar of the period and the workouts themselves, newest first; Diff, what
/// changed since the period's first day; and Gaps, each muscle group's sets. "Log" is the bar's
/// own inline title, centered, with ++ leading. It opens on History each time the drawer shows
/// it. The period is `LogPeriod`'s four calendar weeks, and the three tabs name its first day.
/// Purple marks every logged number and green only a gain; nothing else on it is green. A
/// logged workout's row pushes it, read-only, with the system push, as a saved workout is
/// pushed on Workouts.
struct LogScreen: View {
    @Bindable var session: RoutineSession

    enum Tab: Hashable, CaseIterable {
        case history
        case diff
        case gaps

        var title: String {
            switch self {
            case .history: "History"
            case .diff: "Diff"
            case .gaps: "Gaps"
            }
        }
    }

    /// View state: it starts on History each time Log opens from the drawer, and holds across a
    /// push and pop, since the stack keeps its root.
    @State var tab = Tab.history
    /// The scroll view's height inside its bars, for the empty History to fill.
    @State private var visibleHeight: CGFloat = 0
    @Environment(\.locale) var locale

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
                .padding(.bottom, Spacing.md)
                // With nothing logged, History's line and Go to Workouts center in the room
                // under the calendar.
                .frame(height: isHistoryEmpty ? visibleHeight : nil, alignment: .top)
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
            }
        }
        .task { await session.refreshLog() }
    }

    @ViewBuilder
    private func tabContent(_ log: WorkoutLog) -> some View {
        switch tab {
        case .history: historyTab(log)
        case .diff: diffTab(log)
        case .gaps: gapsTab(log)
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

    /// Workouts at the root, as the drawer's Workouts row shows it, never pushed onto Log.
    func goToWorkouts() {
        session.showRoutines()
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
        session: RoutineSession(
            routine: Routine(name: "Upper body"),
            store: nil,
            namer: .muscleGroupsOnly,
        ),
    )
}
