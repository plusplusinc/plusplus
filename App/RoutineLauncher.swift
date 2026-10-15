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

    @State private var routine: Routine?
    @Environment(\.locale) private var locale
    @ObserveHotReload private var hotReload

    var body: some View {
        Group {
            if let routine {
                RoutineScreen(routine: routine, store: store, namer: namer)
            } else {
                Color.pp(.background)
                    .ignoresSafeArea()
                    .task { routine = await launchRoutine() }
            }
        }
        .hotReloadable()
    }

    private func launchRoutine() async -> Routine {
        guard let store else { return Routine() }
        do {
            #if DEBUG
            if resetsStore {
                try await store.deleteAll()
            }
            #endif
            return try await store
                .launchRoutine(weightUnit: WeightUnit(region: locale)) ?? Routine()
        } catch {
            Logger.app.error("Opening a new routine: the saved one didn't load: \(error)")
            return Routine()
        }
    }
}

#Preview {
    RoutineLauncher(store: nil, namer: .muscleGroupsOnly, resetsStore: false)
}
