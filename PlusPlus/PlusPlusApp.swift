import SwiftUI
import SwiftData
import UIKit

@main
struct PlusPlusApp: App {
    let modelContainer: ModelContainer

    /// Appearance (#97): system by default; the setting lives in the
    /// Settings sheet.
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw: String = AppAppearance.system.rawValue

    init() {
        let schema = Schema([Routine.self, Exercise.self, Equipment.self, WorkoutSession.self, SetLog.self])
        // UI tests pass --uitest-reset so every launch starts from a clean,
        // throwaway store (seed data still loads).
        let inMemory = CommandLine.arguments.contains("--uitest-reset")
        // XCUITest waits for animations to settle before every event and
        // query; on a loaded CI simulator that wait can starve the whole
        // run ("App animations complete notification not received"). Kill
        // animations outright under test.
        if inMemory {
            UIView.setAnimationsEnabled(false)
            // Smoke tests start past setup (the seeded store has
            // routines, so only the stored equipment flag needs
            // forcing); a dedicated flag opts back in for a
            // setup-flow test.
            let onboarding = CommandLine.arguments.contains("--uitest-onboarding")
            UserDefaults.standard.set(!onboarding, forKey: SetupState.equipmentDoneKey)
        }
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        SeedData.loadIfNeeded(context: modelContainer.mainContext)
        // A routine tall enough to overflow every simulator screen, for
        // the scroll regression test. Only meaningful with --uitest-reset.
        if inMemory && CommandLine.arguments.contains("--uitest-bigworkout") {
            Self.seedBigRoutine(context: modelContainer.mainContext)
        }
        RestNotifier.shared.activate()
        WatchBridge.shared.activate(container: modelContainer)
    }

    /// 16 rows guarantees the rail overflows the viewport at every
    /// supported Dynamic Type size on every simulator device.
    private static func seedBigRoutine(context: ModelContext) {
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)]))) ?? []
        guard !exercises.isEmpty else { return }
        let routine = Routine(name: "Big Day", order: 0)
        context.insert(routine)
        for n in 0..<16 {
            routine.addExerciseInNewGroup(exercises[n % exercises.count], context: context)
        }
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme((AppAppearance(rawValue: appearanceRaw) ?? .system).colorScheme)
                // Dynamic Type everywhere (#82), capped where the dense
                // layouts stop coping — full a11y sizes are future work.
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
        .modelContainer(modelContainer)
        // Any edits made this foreground stint reach the wrist before
        // the phone goes in the gym bag.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                WatchBridge.shared.pushPlan()
            }
        }
    }
}
