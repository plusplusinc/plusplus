import SwiftUI
import SwiftData
import UIKit

@main
struct PlusPlusApp: App {
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([Workout.self, Exercise.self, Equipment.self, WorkoutSession.self, SetLog.self])
        // UI tests pass --uitest-reset so every launch starts from a clean,
        // throwaway store (seed data still loads).
        let inMemory = CommandLine.arguments.contains("--uitest-reset")
        // XCUITest waits for animations to settle before every event and
        // query; on a loaded CI simulator that wait can starve the whole
        // run ("App animations complete notification not received"). Kill
        // animations outright under test.
        if inMemory {
            UIView.setAnimationsEnabled(false)
        }
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        SeedData.loadIfNeeded(context: modelContainer.mainContext)
        RestNotifier.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WorkoutListView()
                .preferredColorScheme(.dark) // v2 is dark-only (#59)
                // Dynamic Type everywhere (#82), capped where the dense
                // layouts stop coping — full a11y sizes are future work.
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
        .modelContainer(modelContainer)
    }
}
