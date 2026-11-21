import DesignSystem
import OSLog
import Session
import SwiftUI
import WorkoutStore

/// Opens the routine the app launches into before showing it, so the title never shows New
/// routine and then the saved name.
struct RoutineLauncher: View {
    let store: Store?
    let namer: WorkoutNamer
    let resetsStore: Bool

    @State private var session: RoutineSession?
    @Environment(\.locale) private var locale

    var body: some View {
        if let session {
            // A routine pushed onto the Routines screen takes the edge swipe back, and a workout,
            // or a row's sheet asked for, keeps the drawer shut: the swipe never begins, and the
            // session refuses any other open. A swipe under way keeps a row's sheet out.
            SideDrawer(
                isOpen: Binding {
                    session.isDrawerOpen
                } set: { isOpen in
                    isOpen ? session.openDrawer() : session.closeDrawer()
                },
                isHeld: Binding { session.isDrawerHeld } set: { session.holdDrawer($0) },
                swipeOpens: session.screen != .pushedRoutine && !session.isDrawerLocked
                    && session.rowSheet == nil,
            ) {
                DrawerMenu(session: session)
            } content: {
                switch session.screen {
                case .routine:
                    // A switch to another routine gives a fresh screen: scroll, sheets,
                    // and title.
                    RoutineScreen(session: session, namer: namer)
                        .id(session.opened.id)
                case .routines, .pushedRoutine:
                    RoutinesScreen(session: session, namer: namer)
                }
            }
            .keepsScreenOn(session.loggedWorkout != nil)
        } else {
            Color.pp(.background)
                .ignoresSafeArea()
                .task {
                    let launch = await launch()
                    let session = await RoutineSession(
                        routine: launch.routine,
                        loggedWorkout: launch.loggedWorkout,
                        exercises: exercises(),
                        store: store,
                        namer: namer,
                    )
                    // A timed set that ran out while the app was away is logged, before the
                    // screen opens on the workout.
                    session.catchUp(override: RoutineScreen.restOverride)
                    self.session = session
                    // Read ahead, so the Routines screen's first showing has its list.
                    await session.refreshRecent(weightUnit: WeightUnit(region: locale))
                }
        }
    }

    /// Read after `launch()`, which may reset the store first.
    private func exercises() async -> ExerciseList {
        guard let store else { return .builtIn }
        do {
            return try await store.exercises()
        } catch {
            Logger.app.error("Only the built-in exercises: the created ones didn't load: \(error)")
            return .builtIn
        }
    }

    private func launch() async -> (routine: Workout, loggedWorkout: LoggedWorkout?) {
        guard let store else { return (Workout(), nil) }
        do {
            #if DEBUG
            if resetsStore {
                try await LaunchOptions.resetStore(
                    store,
                    weightUnit: WeightUnit(region: locale),
                    namer: namer,
                )
            }
            #endif
            let launch = try await store.launch(weightUnit: WeightUnit(region: locale))
            return (launch.workout ?? Workout(), launch.loggedWorkout)
        } catch {
            Logger.app.error("Opening a new routine: the saved one didn't load: \(error)")
            return (Workout(), nil)
        }
    }
}

#Preview {
    RoutineLauncher(store: nil, namer: .muscleGroupsOnly, resetsStore: false)
}
