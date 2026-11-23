import DesignSystem
import OSLog
import Session
import SwiftUI
import WorkoutStore

/// Opens where the app launches (`Store.Launch`) before showing it: the workout, so the title
/// never shows New workout and then the saved name, or, after a finish, the Workouts list with
/// its rows already read.
struct WorkoutLauncher: View {
    let store: Store?
    let namer: WorkoutNamer
    let resetsStore: Bool

    @State private var session: AppSession?
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if let session {
            // A workout pushed onto the Workouts screen takes the edge swipe back, and one in
            // progress, or a row's sheet asked for, keeps the drawer shut: the swipe never begins,
            // and the session refuses any other open. A swipe under way keeps a row's sheet out.
            SideDrawer(
                isOpen: Binding {
                    session.isDrawerOpen
                } set: { isOpen in
                    isOpen ? session.openDrawer() : session.closeDrawer()
                },
                isHeld: Binding { session.isDrawerHeld } set: { session.holdDrawer($0) },
                swipeOpens: !session.screen.isPushed && !session.isDrawerLocked
                    && session.rowSheet == nil,
            ) {
                DrawerMenu(session: session)
            } content: {
                switch session.screen {
                case .workout:
                    // A switch to another workout gives a fresh screen: scroll, sheets,
                    // and title.
                    WorkoutScreen(session: session, namer: namer)
                        .id(session.opened.id)
                case .workouts, .pushedWorkout:
                    WorkoutsScreen(session: session, namer: namer)
                case .log, .loggedWorkout:
                    LogScreen(session: session)
                }
            }
            .keepsScreenOn(session.loggedWorkout != nil)
            // A way through the drawer that the app leaves mid-way lands where it was going,
            // closed.
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    session.finishThroughDrawer()
                }
            }
        } else {
            Color.pp(.background)
                .ignoresSafeArea()
                .task {
                    let launch = await launch()
                    let session = await AppSession(
                        launch: launch,
                        exercises: exercises(),
                        store: store,
                        namer: namer,
                    )
                    // A timed set that ran out while the app was away is logged, before the
                    // screen opens on the workout.
                    session.catchUp(override: WorkoutScreen.restOverride)
                    let weightUnit = WeightUnit(region: locale)
                    // On the Workouts list, after a finish, the list is read before the first
                    // frame, so it never shows empty and then fills.
                    if session.screen == .workouts {
                        await session.refreshRecent(weightUnit: weightUnit)
                        self.session = session
                    } else {
                        self.session = session
                        // Read ahead, so the Workouts screen's first showing has its list.
                        await session.refreshRecent(weightUnit: weightUnit)
                    }
                    await session.refreshLog()
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

    private func launch() async -> Store.Launch {
        guard let store else { return .newWorkout }
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
            return try await store.launch(weightUnit: WeightUnit(region: locale))
        } catch {
            Logger.app.error("Opening a new workout: the saved one didn't load: \(error)")
            return .newWorkout
        }
    }
}

#Preview {
    WorkoutLauncher(store: nil, namer: .muscleGroupsOnly, resetsStore: false)
}
