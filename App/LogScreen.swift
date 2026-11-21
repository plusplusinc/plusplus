import DesignSystem
import Session
import SwiftUI
import WorkoutStore

/// The record of finished workouts, read three ways in the system's segmented control under the
/// bar: Workouts, a calendar of the period and the workouts themselves, newest first; Diff, what
/// changed since the period's first day; and Gaps, what has been left alone. "Log" is the bar's
/// own inline title, centered, with ++ leading. It opens on Workouts each time the drawer shows
/// it. The period is `LogPeriod`'s four calendar weeks, and the three tabs name its first day.
/// Purple marks every logged number and green only a gain; nothing else on it is green. A
/// workout's row pushes it, read-only, with the system push, as a routine is pushed on Routines.
struct LogScreen: View {
    @Bindable var session: RoutineSession

    enum Tab: Hashable, CaseIterable {
        case workouts
        case diff
        case gaps

        var title: String {
            switch self {
            case .workouts: "Workouts"
            case .diff: "Diff"
            case .gaps: "Gaps"
            }
        }
    }

    /// View state: it starts on Workouts each time Log opens from the drawer, and holds across a
    /// push and pop, since the stack keeps its root.
    @State var tab = Tab.workouts
    /// The scroll view's height inside its bars, for the empty Workouts to fill.
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
                    .padding(.bottom, Spacing.md)
                    if let log = session.log {
                        tabContent(log)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.md)
                // With nothing logged, Workouts' line and Go to Routines center in the room
                // under the calendar.
                .frame(height: isWorkoutsEmpty ? visibleHeight : nil, alignment: .top)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.containerSize.height - geometry.contentInsets.top
                    - geometry.contentInsets.bottom
            } action: { _, height in
                visibleHeight = height
            }
            .accessibilityHidden(session.isDrawerOpen)
            .background { Color.pp(.background).ignoresSafeArea() }
            .navigationDestination(item: pushedWorkout) { id in
                if let log = session.log, let workout = log.workout(id: id) {
                    LoggedWorkoutScreen(workout: workout, log: log, exercises: session.exercises)
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
        case .workouts: workoutsTab(log)
        case .diff: diffTab(log)
        case .gaps: gapsTab(log)
        }
    }

    private var isWorkoutsEmpty: Bool {
        tab == .workouts && session.log?.workouts.isEmpty == true
    }

    /// The pushed workout, which the back button and the back swipe pop.
    private var pushedWorkout: Binding<Workout.ID?> {
        Binding {
            if case let .loggedWorkout(id) = session.screen {
                id
            } else {
                nil
            }
        } set: { id in
            if let id {
                session.openWorkout(id)
            } else {
                session.popWorkout()
            }
        }
    }

    func openWorkout(_ id: Workout.ID) {
        session.openWorkout(id)
    }

    /// Routines at the root, as the drawer's Routines row shows it, never pushed onto Log.
    func goToRoutines() {
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
