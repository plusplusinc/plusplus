import DesignSystem
import OSLog
import SwiftUI
import WorkoutStore

/// Opens the routine the app launches into before showing it, so the title never shows New
/// routine and then the saved name.
struct RoutineLauncher: View {
    let store: RoutineStore?
    let namer: RoutineNamer
    let resetsStore: Bool

    @State private var session: RoutineSession?
    @Environment(\.locale) private var locale
    @ObserveHotReload private var hotReload

    var body: some View {
        Group {
            if let session {
                @Bindable var session = session
                // A routine pushed onto the Routines screen takes the edge swipe back to the list,
                // and a workout keeps the drawer shut.
                SideDrawer(
                    isOpen: $session.isDrawerOpen,
                    swipeOpens: !session.isRoutinePushed && !session.isDrawerLocked,
                ) {
                    DrawerMenu(session: session, namer: namer)
                } content: {
                    switch session.screen {
                    case .routine:
                        // A switch to another routine gives a fresh screen: scroll, sheets,
                        // and title.
                        RoutineScreen(session: session, namer: namer)
                            .id(session.opened.id)
                    case .routines:
                        RoutinesScreen(session: session, namer: namer)
                    }
                }
                .keepsScreenOn(session.workout != nil)
            } else {
                Color.pp(.background)
                    .ignoresSafeArea()
                    .task {
                        let launch = await launch()
                        let session = RoutineSession(
                            routine: launch.routine,
                            workout: launch.workout,
                            store: store,
                        )
                        self.session = session
                        // The drawer names the routine last opened, which may not be this one.
                        await session.refreshRecent(weightUnit: WeightUnit(region: locale))
                    }
            }
        }
        .hotReloadable()
    }

    private func launch() async -> (routine: Routine, workout: Workout?) {
        guard let store else { return (Routine(), nil) }
        do {
            #if DEBUG
            if resetsStore {
                try await store.deleteAll()
                if let seed = LaunchOptions.seededRoutine {
                    let unit = WeightUnit(region: locale)
                    try await store.save(Routine(
                        name: seed.name,
                        exercises: seed.exercises.map { RoutineExercise(
                            exercise: $0,
                            weightUnit: unit,
                        ) },
                    ))
                }
            }
            #endif
            let launch = try await store.launch(weightUnit: WeightUnit(region: locale))
            return (launch.routine ?? Routine(), launch.workout)
        } catch {
            Logger.app.error("Opening a new routine: the saved one didn't load: \(error)")
            return (Routine(), nil)
        }
    }
}

#Preview {
    RoutineLauncher(store: nil, namer: .muscleGroupsOnly, resetsStore: false)
}
