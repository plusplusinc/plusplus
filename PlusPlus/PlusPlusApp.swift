import SwiftUI
import SwiftData

@main
struct PlusPlusApp: App {
    @AppStorage("appearance") private var appearance: AppAppearance = .dark
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([Workout.self, Exercise.self, Equipment.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
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
