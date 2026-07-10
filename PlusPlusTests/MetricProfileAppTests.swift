import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

@Suite("Metric profiles — catalog assignment")
struct CatalogProfileTests {
    @Test("Every built-in resolves a valid profile consistent with its legacy type")
    func allProfilesValid() {
        var checked = 0
        // The definitions table is the source of truth — resolve every
        // entry and hold it to the profile laws.
        let exercises = SeedData.makeBuiltInExercisesForTesting(equipment: [])
        for exercise in exercises {
            guard let profile = SeedData.builtInProfile(named: exercise.name) else {
                Issue.record("no profile for \(exercise.name)")
                continue
            }
            #expect(profile.isValid, "\(exercise.name) profile lacks a work metric")
            #expect(profile.legacyType == exercise.exerciseType,
                    "\(exercise.name): profile says \(profile.legacyType) but definition says \(exercise.exerciseType)")
            checked += 1
        }
        #expect(checked == SeedData.builtInExerciseCount)
    }

    @Test("The evaluation's key assignments hold")
    func keyAssignments() {
        #expect(SeedData.builtInProfile(named: "Bench Press") == .weightReps)
        // Bodyweight rep work drops the dead weight row.
        #expect(SeedData.builtInProfile(named: "Push-Up") == .repsOnly)
        #expect(SeedData.builtInProfile(named: "Pull-Up") == .repsOnly)
        // Ergs: distance-first with damper, split, and time.
        #expect(SeedData.builtInProfile(named: "Rowing")
                == MetricProfile([.distance, .duration, .pace, .resistance]))
        // The air bike prescribes in calories and watts.
        #expect(SeedData.builtInProfile(named: "Assault Bike")
                == MetricProfile([.duration, .calories, .power]))
        // Treadmill: miles, speed, incline.
        #expect(SeedData.builtInProfile(named: "Treadmill Run")
                == MetricProfile([.distance, .duration, .speed, .incline], distanceUnit: .miles))
        // Assisted machines: the stack subtracts.
        #expect(SeedData.builtInProfile(named: "Assisted Pull-Up")
                == MetricProfile([.assistance, .reps]))
        // Plyo: height × reps.
        #expect(SeedData.builtInProfile(named: "Box Jump")
                == MetricProfile([.height, .reps]))
        // Carries: load over ground (+ the loadable's weight).
        #expect(SeedData.builtInProfile(named: "Yoke Carry")
                == MetricProfile([.weight, .distance, .duration]))
        #expect(SeedData.builtInProfile(named: "Farmer's Carry")
                == MetricProfile([.weight, .duration]))
        // Holds stay plain duration.
        #expect(SeedData.builtInProfile(named: "Plank") == .durationOnly)
        // The explicit overrides.
        #expect(SeedData.builtInProfile(named: "Ruck")
                == MetricProfile([.weight, .distance, .duration], distanceUnit: .miles))
        #expect(SeedData.builtInProfile(named: "Running")
                == MetricProfile([.distance, .duration, .pace], distanceUnit: .miles))
    }

    @Test("Equipment-free cardio joined the catalog")
    func newCardioExercises() {
        for name in ["Running", "Walking", "Cycling"] {
            #expect(SeedData.builtInDefinition(named: name) != nil, "\(name) missing")
            #expect(SeedData.builtInDefinition(named: name)?.equipmentNames.isEmpty == true)
        }
    }

    @Test("Every equipment-profile entry names real gear")
    func equipmentProfileNamesResolve() {
        let equipmentNames = Set(SeedData.builtInEquipment.map(\.name))
        for name in SeedData.equipmentProfiles.keys {
            #expect(equipmentNames.contains(name), "\(name) not in the equipment catalog")
        }
    }

    @Test("Custom equipment loadability follows its declared profile")
    func customLoadability() {
        let undeclared = Equipment(name: "Mystery Machine")
        #expect(SeedData.isLoadable(undeclared))
        let spinBike = Equipment(name: "Spin Bike")
        spinBike.suggestedProfile = MetricProfile([.duration, .resistance, .cadence])
        #expect(!SeedData.isLoadable(spinBike))
        let customBar = Equipment(name: "Curl Bar 2")
        customBar.suggestedProfile = .weightReps
        #expect(SeedData.isLoadable(customBar))
    }

    @Test("Suggested profiles merge gear, loadability, and a work-metric guarantee")
    func suggestionMerging() {
        // Loadable strength gear → classic.
        #expect(SeedData.suggestedProfile(type: .weightReps, equipmentNames: ["Barbell", "Bench"])
                == .weightReps)
        // Non-loadable gear → bare reps.
        #expect(SeedData.suggestedProfile(type: .weightReps, equipmentNames: ["Pull-Up Bar"])
                == .repsOnly)
        // A loadable + the plyo box: union + weight.
        #expect(SeedData.suggestedProfile(type: .weightReps, equipmentNames: ["Dumbbells", "Plyo Box"])
                == MetricProfile([.weight, .reps, .height]))
        // Assistance speaks for the load — no weight added.
        #expect(SeedData.suggestedProfile(type: .weightReps, equipmentNames: ["Assisted Pull-Up Machine"])
                == MetricProfile([.assistance, .reps]))
        // Duration on loadable gear (a kettlebell carry).
        #expect(SeedData.suggestedProfile(type: .duration, equipmentNames: ["Kettlebell"])
                == MetricProfile([.weight, .duration]))
    }
}

@Suite("Metric profiles — models")
struct ModelProfileTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self, Equipment.self, Routine.self, ExerciseGroup.self,
            RoutineExercise.self, WorkoutSession.self, SetLog.self,
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("metricprofile-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// A rower exercise + a 4×500m interval routine with a 2-minute
    /// block rest — the canonical interval shape.
    private func makeErgRoutine(context: ModelContext) -> (Routine, Exercise) {
        let erg = Exercise(name: "Probe Row", muscleGroup: .fullBody, exerciseType: .duration)
        context.insert(erg)
        erg.metricProfile = MetricProfile([.distance, .duration, .pace, .resistance])

        let routine = Routine(name: "Probe Intervals", restSeconds: 90)
        context.insert(routine)
        let group = routine.addExerciseInNewGroup(erg, context: context)
        group.sets = 4
        group.restSecondsOverride = 120
        let entry = group.sortedExercises[0]
        entry.setTarget(.distance, to: 500)
        entry.setTarget(.resistance, to: 5)
        return (routine, erg)
    }

    @Test("Profile resolution: explicit > catalog table > legacy type")
    func resolutionOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Built-in without stored profile → the catalog's assignment.
        let rowing = Exercise(name: "Rowing", muscleGroup: .fullBody, exerciseType: .duration, isBuiltIn: true)
        context.insert(rowing)
        #expect(rowing.metricProfile == MetricProfile([.distance, .duration, .pace, .resistance]))

        // Legacy custom without stored profile → derived from type.
        let custom = Exercise(name: "Probe Custom", muscleGroup: .chest)
        context.insert(custom)
        #expect(custom.metricProfile == .weightReps)

        // Explicit storage wins and syncs the legacy type.
        rowing.metricProfile = MetricProfile([.duration])
        #expect(rowing.metricProfile == .durationOnly)
        #expect(rowing.exerciseType == .duration)
    }

    @Test("Interval blocks: snapshot profile, extras, rest override, distance driver")
    func intervalSession() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (routine, _) = makeErgRoutine(context: context)

        let session = WorkoutSession.start(from: routine, context: context)
        let logs = session.sortedSetLogs
        #expect(logs.count == 4)
        let first = try #require(logs.first)
        #expect(first.metricProfile == MetricProfile([.distance, .duration, .pace, .resistance]))
        #expect(first.target(.distance) == 500)
        #expect(first.target(.resistance) == 5)
        #expect(first.restSecondsOverride == 120)
        #expect(session.restSeconds(after: first) == 120)
        #expect(first.driver == .distance)

        // Completing prefills every tracked actual from its target.
        session.complete(first)
        #expect(first.actual(.distance) == 500)
        #expect(first.actual(.resistance) == 5)

        // A mid-session damper change carries to the remaining rounds.
        let second = logs[1]
        second.setActual(.resistance, to: 7)
        session.complete(second)
        #expect(logs[2].target(.resistance) == 7)
        #expect(logs[3].target(.resistance) == 7)
        // But the work target never carries.
        second.setActual(.distance, to: 600)
        #expect(logs[2].target(.distance) == 500)
    }

    @Test("Duration-targeted blocks keep the timer driver")
    func durationDriver() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (routine, _) = makeErgRoutine(context: context)
        let entry = routine.sortedGroups[0].sortedExercises[0]
        entry.setTarget(.distance, to: nil)
        entry.setTarget(.duration, to: 1200)

        let session = WorkoutSession.start(from: routine, context: context)
        #expect(session.sortedSetLogs.first?.driver == .duration)
    }

    @Test("appendExercise never fabricates a work target for cardio profiles")
    func appendCardio() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (_, erg) = makeErgRoutine(context: context)
        erg.extraDefaults = [.distance: 2000, .resistance: 5]

        let session = WorkoutSession.startEmpty(context: context)
        let appended = session.appendExercise(erg, context: context)
        let log = try #require(appended.first)
        // Defaults arrive; no invented 45 s duration to hijack the driver.
        #expect(log.target(.distance) == 2000)
        #expect(log.targetDuration == nil)
        #expect(log.driver == .distance)

        // Classic profiles keep their startable floor targets.
        let plank = Exercise(name: "Probe Plank", muscleGroup: .core, exerciseType: .duration)
        context.insert(plank)
        let plankLog = try #require(session.appendExercise(plank, context: context).first)
        #expect(plankLog.targetDuration == 45)
    }

    @Test("Routine edits bump extras into exercise defaults")
    func bumpDefaults() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (routine, erg) = makeErgRoutine(context: context)
        let entry = routine.sortedGroups[0].sortedExercises[0]

        entry.setTarget(.pace, to: 118)
        entry.bumpExerciseDefaults()
        #expect(erg.extraDefaults[.distance] == 500)
        #expect(erg.extraDefaults[.pace] == 118)
        #expect(erg.defaultTarget(.resistance) == 5)
    }

    @Test("saveAsRoutine materializes cardio blocks with extras and rest")
    func saveScratchCardio() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let erg = Exercise(name: "Probe Row", muscleGroup: .fullBody, exerciseType: .duration)
        context.insert(erg)
        erg.metricProfile = MetricProfile([.distance, .duration, .resistance])
        erg.extraDefaults = [.distance: 500]

        let session = WorkoutSession.startEmpty(context: context)
        let logs = session.appendExercise(erg, sets: 2, context: context)
        for log in logs {
            log.restSecondsOverride = 120
            log.setActual(.distance, to: 500)
            log.setActual(.duration, to: 110)
            log.setActual(.resistance, to: 6)
            session.complete(log)
        }
        session.finish()

        let routine = try #require(session.saveAsRoutine(named: "Erg Day", among: [], context: context))
        let group = try #require(routine.sortedGroups.first)
        #expect(group.sets == 2)
        #expect(group.restSecondsOverride == 120)
        let entry = try #require(group.sortedExercises.first)
        #expect(entry.target(.distance) == 500)
        #expect(entry.target(.resistance) == 6)
        #expect(entry.durationSeconds == 110)
    }

    @Test("Interchange round-trips profiles, extras, and rest overrides")
    func mappingRoundTrip() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let (routine, erg) = makeErgRoutine(context: context)
        erg.extraDefaults = [.distance: 2000]

        let session = WorkoutSession.start(from: routine, context: context)
        for log in session.sortedSetLogs {
            session.complete(log)
        }
        session.finish()
        try context.save()

        let bundle = try InterchangeMapping.exportBundle(context: context)
        #expect(InterchangeValidator.validate(bundle).isEmpty)
        let exercise = try #require(bundle.exercises.first { $0.name == "Probe Row" })
        #expect(exercise.metrics == ["distance", "duration", "pace", "resistance"])
        #expect(exercise.extraDefaults == ["distance": 2000])
        let group = try #require(bundle.routines.first?.groups.first)
        #expect(group.restSeconds == 120)
        #expect(group.exercises.first?.extraTargets == ["distance": 500, "resistance": 5])
        let set = try #require(bundle.sessions.first?.sets.first)
        #expect(set.extraActuals?["distance"] == 500)
        #expect(set.restSecondsOverride == 120)

        // Import into a fresh store: everything lands.
        let freshContainer = try makeContainer()
        let freshContext = ModelContext(freshContainer)
        try InterchangeMapping.importBundle(bundle, context: freshContext)
        let imported = try #require(
            try freshContext.fetch(FetchDescriptor<Exercise>()).first { $0.name == "Probe Row" }
        )
        #expect(imported.metricProfile == MetricProfile([.distance, .duration, .pace, .resistance]))
        #expect(imported.extraDefaults == [.distance: 2000])
        let importedSession = try #require(try freshContext.fetch(FetchDescriptor<WorkoutSession>()).first)
        let importedLog = try #require(importedSession.sortedSetLogs.first)
        #expect(importedLog.extraActuals[.distance] == 500)
        #expect(importedLog.restSecondsOverride == 120)
        // The reconstructed snapshot lets history render every value.
        #expect(importedLog.metricProfile.contains(.resistance))
    }

    @Test("Assistance falls back to the legacy weight column for old logs")
    func assistanceFallback() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let log = SetLog(order: 0, groupIndex: 0, setNumber: 1, exerciseName: "Assisted Pull-Up")
        context.insert(log)
        log.actualWeight = 60
        #expect(log.actual(.assistance) == 60)
        log.setActual(.assistance, to: 50)
        #expect(log.actual(.assistance) == 50)
    }
}

@Suite("ExerciseDraft (flexible metrics)")
struct DraftProfileTests {
    @Test("A profile without a work metric can't save")
    func validation() {
        let draft = ExerciseDraft()
        draft.name = "Probe"
        #expect(draft.canSave(existingNames: []))
        draft.trackedMetrics = [.weight]
        #expect(!draft.canSave(existingNames: []))
        draft.trackedMetrics = [.weight, .distance]
        #expect(draft.canSave(existingNames: []))
    }

    @Test("Prefill adopts gear suggestions until the user touches the chips")
    func prefillLatch() {
        let draft = ExerciseDraft()
        let rower = MetricProfile([.distance, .duration, .pace, .resistance])
        draft.adoptSuggestedProfile(rower)
        #expect(draft.metricProfile == rower)
        draft.toggleMetric(.pace)
        #expect(!draft.isTracked(.pace))
        // A later equipment change must not clobber the explicit choice.
        draft.adoptSuggestedProfile(.weightReps)
        #expect(draft.metricProfile == MetricProfile([.distance, .duration, .resistance]))
    }

    @Test("apply prunes defaults for untracked metrics and stores only real customization")
    func applyPruning() throws {
        let schema = Schema([Exercise.self, Equipment.self])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("draft-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let exercise = Exercise(name: "Probe", muscleGroup: .chest)
        context.insert(exercise)
        let draft = ExerciseDraft(from: exercise)
        draft.defaultWeight = 45
        draft.defaultReps = 10
        draft.extraDefaults = [.distance: 500]
        draft.trackedMetrics = [.reps]
        draft.apply(to: exercise)
        // Weight and distance aren't tracked — their defaults dropped.
        #expect(exercise.defaultWeight == nil)
        #expect(exercise.defaultReps == 10)
        #expect(exercise.extraDefaults.isEmpty)
        #expect(exercise.metricProfile == .repsOnly)
        // repsOnly ≠ the type-derived fallback → stored explicitly.
        #expect(exercise.metricsData != nil)

        // Back to the classic pair: matches the fallback → unstored.
        let draft2 = ExerciseDraft(from: exercise)
        draft2.trackedMetrics = [.weight, .reps]
        draft2.apply(to: exercise)
        #expect(exercise.metricsData == nil)
        #expect(exercise.metricProfile == .weightReps)
    }
}
