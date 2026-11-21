import DesignSystem
import Session
import SwiftUI
import WorkoutStore

/// The record of finished workouts, read three ways in the system's segmented control:
/// Workouts, the workouts themselves, newest first; Progress, what went up over four weeks; and
/// Gaps, what has been left alone. It opens on Workouts each time the drawer shows it. Purple
/// marks every logged number and green only a gain; nothing else on it is green. A workout's row
/// pushes it, read-only, with the system push, as a routine is pushed on Routines.
struct LogScreen: View {
    @Bindable var session: RoutineSession

    enum Tab: Hashable, CaseIterable {
        case workouts
        case progress
        case gaps

        var title: String {
            switch self {
            case .workouts: "Workouts"
            case .progress: "Progress"
            case .gaps: "Gaps"
            }
        }

        /// What the tab will hold, in place of its rows while it has none. Gaps has none: with
        /// no workouts it shows every group at 0.
        var emptyText: String? {
            switch self {
            case .workouts: "Finished workouts show up here."
            case .progress: "Exercises done in two workouts show up here."
            case .gaps: nil
            }
        }
    }

    /// View state: it starts on Workouts each time Log opens from the drawer, and holds across a
    /// push and pop, since the stack keeps its root.
    @State var tab = Tab.workouts
    @State private var scrollPosition = ScrollPosition()
    @State private var isTitleUnderBar = false
    @Environment(\.locale) var locale

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Log")
                        .ppFixedTitleFont()
                        .foregroundStyle(.pp(.textPrimary))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, Spacing.md)
                        .onScrollVisibilityChange(threshold: 0.01) { isVisible in
                            withAnimation(.easeOut(duration: RoutineScreen.barFade)) {
                                isTitleUnderBar = !isVisible
                            }
                        }
                    Picker("Show", selection: $tab) {
                        ForEach(Tab.allCases, id: \.self) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, Spacing.sm)
                    // With nothing to show, the tab draws nothing but the empty line over it.
                    if let log = session.log, emptyText == nil {
                        tabContent(log)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.md)
            }
            .scrollPosition($scrollPosition)
            .emptyNote(emptyText ?? "", isEmpty: emptyText != nil)
            .accessibilityHidden(session.isDrawerOpen)
            .background { Color.pp(.background).ignoresSafeArea() }
            .navigationDestination(item: pushedWorkout) { id in
                if let log = session.log, let workout = log.workout(id: id) {
                    LoggedWorkoutScreen(workout: workout, log: log, exercises: session.exercises)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .title) {
                    Button {
                        withAnimation(.snappy) { scrollPosition.scrollTo(edge: .top) }
                    } label: {
                        Text("Log")
                            .font(.ppBarTitle)
                            .foregroundStyle(.pp(.textPrimary))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHint("Scrolls to the top.")
                    .hiddenBehindDrawer()
                    .opacity(isTitleUnderBar ? 1 : 0)
                    .allowsHitTesting(isTitleUnderBar)
                    .accessibilityShown(isTitleUnderBar)
                }
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
        case .workouts: workoutRows(log)
        case .progress: progressRows(log)
        case .gaps: gapRows(log)
        }
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
