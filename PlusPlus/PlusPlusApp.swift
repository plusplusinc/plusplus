import SwiftUI
import SwiftData

@main
struct PlusPlusApp: App {
    @AppStorage("appearance") private var appearance: AppAppearance = .dark
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([Workout.self, Exercise.self, Equipment.self, WorkoutSession.self, SetLog.self])
        // UI tests pass --uitest-reset so every launch starts from a clean,
        // throwaway store (seed data still loads).
        let inMemory = CommandLine.arguments.contains("--uitest-reset")
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        SeedData.loadIfNeeded(context: modelContainer.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            WorkoutListView()
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(modelContainer)
    }
}
