import SwiftUI
import SwiftData
import TipKit
import UIKit
import PlusPlusKit

@main
struct PlusPlusApp: App {
    let modelContainer: ModelContainer

    /// True when this process hosts the unit-test bundle. The host must
    /// stay inert: tests build their own containers, and launch-time side
    /// effects (TipKit's datastore, WCSession activation, the notification
    /// center, the App Group snapshot) are process-global state racing the
    /// tests. UI tests are unaffected — the app under XCUITest runs in a
    /// separate process with no test bundle injected.
    private static let isUnitTestHost =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
            || NSClassFromString("XCTestCase") != nil

    /// Appearance (#97): system by default; the setting lives in the
    /// Settings sheet.
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw: String = AppAppearance.system.rawValue
    @AppStorage(WeightUnitSetting.key) private var weightUnitRaw: String = WeightUnit.lb.rawValue

    init() {
        // The versioned schema + migration plan (#155). Opening WITH the
        // plan is what lets a future shape change migrate the store instead
        // of resetting it; see AppSchema.swift.
        let schema = AppSchema.latest
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
            // Same rule for the welcome flow: every other test expects
            // the tabs immediately; --uitest-welcome opts one test in.
            let welcome = CommandLine.arguments.contains("--uitest-welcome")
            UserDefaults.standard.set(!welcome, forKey: SetupState.welcomeSeenKey)
        }
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        do {
            modelContainer = try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config])
        } catch {
            guard !inMemory else { fatalError("Failed to create in-memory ModelContainer: \(error)") }
            // #155: before treating the store as unrecoverable, try opening
            // it WITHOUT the plan. Attaching a plan is stricter than the
            // plan-less container that shipped pre-#155 (which relied on
            // SwiftData's implicit lightweight migration for additive drift);
            // a store the empty-stage plan rejects may still open leniently.
            // Only if THAT also fails is the store genuinely unopenable — and
            // then we still never wipe silently: copy the raw store aside,
            // leave a breadcrumb, and recreate.
            if let salvaged = try? ModelContainer(for: schema, configurations: [config]) {
                modelContainer = salvaged
            } else {
                StoreRecovery.backUpAndReset(storeURL: config.url, error: error)
                do {
                    modelContainer = try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config])
                } catch {
                    fatalError("Failed to create ModelContainer even after store reset: \(error)")
                }
                // The store was rebuilt, so the stored setup flag describing
                // the old data is stale too; the rest of the setup timeline
                // self-heals from live data.
                UserDefaults.standard.removeObject(forKey: SetupState.equipmentDoneKey)
            }
        }
        guard !Self.isUnitTestHost else { return }
        // Smoke tests assume a usable library; the onboarding test and
        // real fresh installs start with the catalog only (#185).
        let onboardingTest = CommandLine.arguments.contains("--uitest-onboarding")
        SeedData.loadIfNeeded(
            context: modelContainer.mainContext,
            populateLibrary: inMemory && !onboardingTest
        )
        if !inMemory {
            SeedData.repairBuiltInEquipmentIfNeeded(context: modelContainer.mainContext)
            // After loadIfNeeded (the Bicycle row must exist to attach).
            SeedData.syncRevisedEquipmentRequirementsIfNeeded(context: modelContainer.mainContext)
            SeedData.resetEquipmentOwnershipIfNeeded(context: modelContainer.mainContext)
            // Don't re-prime installs that already trained on a pre-primer
            // build (keyed on real history, not welcomeSeen — which is set
            // at "Get started", before a fresh user's first workout).
            let hasHistory = ((try? modelContainer.mainContext.fetchCount(FetchDescriptor<WorkoutSession>())) ?? 0) > 0
            SetupState.backfillHealthPrimerForExistingInstalls(hasWorkoutHistory: hasHistory)
            // The exercise library became favorites: carry an upgrading
            // store's curated built-ins across so the repo export basis
            // (favorited, not in-library) stays continuous.
            SeedData.adoptLibraryAsFavoritesIfNeeded(context: modelContainer.mainContext)
        }
        // AFTER the legacy one-shots: the libraries migration snapshots
        // the inLibrary flags the reset may have just rewritten.
        SeedData.ensureEquipmentLibrary(context: modelContainer.mainContext)
        // After ensure so the fetch sees settled library state. Targets
        // existing stores whose lone default is still the pre-rename
        // "Home"; fresh + just-migrated stores get "main" straight from
        // the constant above.
        SeedData.renameDefaultKitIfNeeded(context: modelContainer.mainContext)
        // Ensure every routine/group/exercise has a stable uuid — assigns one
        // to any row migrated in from a pre-uuid store (#155).
        SeedData.backfillModelUUIDsIfNeeded(context: modelContainer.mainContext)
        // A routine tall enough to overflow every simulator screen, for
        // the scroll regression test. Only meaningful with --uitest-reset.
        if inMemory && CommandLine.arguments.contains("--uitest-bigworkout") {
            Self.seedBigRoutine(context: modelContainer.mainContext)
        }
        LiveMirror.shared.activate(container: modelContainer)
        // The superset-introduction tips (the only TipKit surface).
        // Daily cadence: with two tips in the pool, HIG wants a
        // frequency so consecutive screens can't stack popovers. Not
        // under UI test: a system popover would eat a smoke test's tap.
        if !inMemory {
            try? Tips.configure([.displayFrequency(.daily)])
        }
        WatchBridge.shared.activate(container: modelContainer)
        WidgetSnapshotWriter.write(container: modelContainer)
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
            if Self.isUnitTestHost {
                Text("unit-test host")
            } else {
                RootTabView()
                    .preferredColorScheme((AppAppearance(rawValue: appearanceRaw) ?? .system).colorScheme)
                    // Dynamic Type everywhere (#82). The old xxLarge cap is
                    // lifted: the full range through AX5 is now reachable
                    // (a11y audit 2026-07-13, #164). The densest fixed-height
                    // controls were hardened for it in the same pass — the
                    // scale net below plus `minHeight`/`@ScaledMetric` on the
                    // capsules, sheets, and rows the swiftui-layout-auditor
                    // flagged — so text scales/grows to fit rather than
                    // clipping. The exact packing of the busiest rows at the
                    // AX4/AX5 extremes still wants an on-device glance.
                    .dynamicTypeSize(...DynamicTypeSize.accessibility5)
                    // NB: no app-wide `minimumScaleFactor` here. A global one
                    // propagates through the environment to EVERY descendant
                    // Text, so any single-line label a touch too wide for its
                    // container silently shrank — even at the default type size
                    // (the #164 net did exactly this: the Health tray status
                    // line rendered at ~half size, and equal-role fields like
                    // the Exercises-list subtitles came out at DIFFERENT sizes
                    // depending on string length). Shrink-to-fit is now local
                    // to the fixed-height capsules/pills/chips that actually
                    // need it (each carries its own `.minimumScaleFactor`);
                    // everything else renders at its true, consistent size and
                    // wraps rather than shrinks.
            }
        }
        .modelContainer(modelContainer)
        // Any edits made this foreground stint reach the wrist before
        // the phone goes in the gym bag.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                WatchBridge.shared.pushPlan()
                WidgetSnapshotWriter.write(container: modelContainer)
                // Reconcile before the user might switch to their calendar
                // app, so a just-made schedule edit is already reflected
                // (#333). A no-op unless calendar sync is on.
                if !Self.isUnitTestHost { reconcileCalendar() }
            } else if phase == .active, !Self.isUnitTestHost {
                // Pull remote changes and push anything logged elsewhere, once
                // per foreground. No-ops unless GitHub sync is connected (#23).
                let units = WeightUnit(rawValue: weightUnitRaw) ?? .lb
                Task { @MainActor in
                    await GitHubSyncCoordinator.shared.sync(
                        context: modelContainer.mainContext, units: units
                    )
                }
                // The reconcile backstop (#333): heals external calendar
                // changes and any schedule edit a specific hook missed.
                reconcileCalendar()
            }
        }
    }

    /// Bring the "++ Workouts" calendar in step with the current routines.
    /// Guarded internally so it costs nothing unless the feature is on.
    @MainActor
    private func reconcileCalendar() {
        Task { @MainActor in
            let routines = (try? modelContainer.mainContext.fetch(FetchDescriptor<Routine>())) ?? []
            await CalendarSyncCoordinator.shared.reconcile(routines: routines)
        }
    }
}
