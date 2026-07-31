import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

@Suite("Routine time estimate")
struct RoutineEstimateTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self, RoutineExercise.self])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("routineestimate-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("Weight sets count 45 s each; timed sets use their target; rest fills rounds, transitions fill boundaries")
    func estimate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "W", restSeconds: 60, transitionSeconds: 15)
        context.insert(routine)

        let bench = Exercise(name: "Probe Press", muscleGroup: .chest)
        let plank = Exercise(name: "Probe Hold", muscleGroup: .core, exerciseType: .duration)
        context.insert(bench)
        context.insert(plank)

        let liftGroup = routine.addExerciseInNewGroup(bench, context: context) // 3 sets default
        let plankGroup = routine.addExerciseInNewGroup(plank, context: context)
        plankGroup.sets = 2
        plankGroup.sortedExercises[0].durationSeconds = 90

        // Work: 3×45 + 2×90 = 315; rest before new rounds: (3-1)×60 +
        // (2-1)×60 = 180; the block boundary is a transition: 15 (#369).
        _ = liftGroup
        #expect(routine.estimatedSeconds == 510)
    }

    @Test("Superset partners hand off on transitions, not rests (#369)")
    func supersetEstimate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "S", restSeconds: 60, transitionSeconds: 15)
        context.insert(routine)

        let curl = Exercise(name: "Probe Curl", muscleGroup: .biceps)
        let press = Exercise(name: "Probe Press", muscleGroup: .chest)
        context.insert(curl)
        context.insert(press)

        let pair = routine.addExerciseInNewGroup(curl, context: context)
        pair.sets = 2
        routine.addExercise(press, to: pair, context: context)

        // Work: 4×45 = 180; within-round handoffs: 1×15×2 rounds = 30;
        // between rounds: (2-1)×60 = 60. No trailing pause.
        #expect(routine.estimatedSeconds == 270)
    }

    @Test("Empty routine estimates zero")
    func emptyEstimate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "W")
        context.insert(routine)
        #expect(routine.estimatedSeconds == 0)
    }

    @Test("A distance-and-pace run multiplies out instead of charging 45 s")
    func cardioEstimate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "R", restSeconds: 60, transitionSeconds: 15)
        context.insert(routine)

        let run = Exercise(name: "Probe Run", muscleGroup: .fullBody, exerciseType: .duration)
        context.insert(run)
        run.metricProfile = MetricProfile([.distance, .duration, .pace], distanceUnit: .miles, isOutdoor: true)

        let group = routine.addExerciseInNewGroup(run, context: context)
        group.sets = 1
        let entry = group.sortedExercises[0]
        entry.durationSeconds = nil
        entry.setTarget(.distance, to: 5)
        entry.setTarget(.pace, to: 540)

        // Five miles at 9:00 is forty-five minutes. This read "45 seconds"
        // before, because any non-duration set was charged a flat 45 —
        // the single most visible lie the app told about cardio.
        #expect(routine.estimatedSeconds == 2700)
        #expect(routine.estimateText == "~45 min")
    }

    @Test("An open-ended effort falls back rather than inventing a number")
    func openEndedEstimate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "R")
        context.insert(routine)

        let run = Exercise(name: "Probe Run", muscleGroup: .fullBody, exerciseType: .duration)
        context.insert(run)
        run.metricProfile = MetricProfile([.distance, .duration, .pace], distanceUnit: .miles, isOutdoor: true)

        let group = routine.addExerciseInNewGroup(run, context: context)
        group.sets = 1
        group.sortedExercises[0].durationSeconds = nil

        // Nothing is knowable, so the per-set charge stands. Better a
        // rough number than a fabricated precise one.
        #expect(routine.estimatedSeconds == Routine.assumedSetSeconds)
    }

    @Test("A distance interval estimates every round")
    func intervalEstimate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "I", restSeconds: 120, transitionSeconds: 15)
        context.insert(routine)

        let erg = Exercise(name: "Probe Erg", muscleGroup: .fullBody, exerciseType: .duration)
        context.insert(erg)
        erg.metricProfile = MetricProfile([.distance, .duration, .pace], distanceUnit: .meters)

        let group = routine.addExerciseInNewGroup(erg, context: context)
        group.sets = 4
        let entry = group.sortedExercises[0]
        entry.durationSeconds = nil
        entry.setTarget(.distance, to: 500)
        entry.setTarget(.pace, to: 120)

        // 500 m at a 2:00 split is 2:00 a piece. Four of them, three
        // 2-minute rests between: 480 + 360.
        #expect(routine.estimatedSeconds == 840)
    }
}

@Suite("Routine modality")
struct RoutineModalityTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self, RoutineExercise.self])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("routinemodality-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("A console routine that tracks neither distance nor pace is still cardio")
    func ellipticalIsCardio() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "E")
        context.insert(routine)

        // The old test was `allSatisfy { tracks distance or pace }`, and an
        // elliptical tracks NEITHER — its profile is duration plus
        // resistance — so the most obviously cardio routine in the app
        // read as strength.
        let elliptical = Equipment(name: "Elliptical")
        context.insert(elliptical)
        let cross = Exercise(name: "Probe Cross", muscleGroup: .fullBody, exerciseType: .duration)
        context.insert(cross)
        cross.equipment = [elliptical]
        cross.metricProfile = MetricProfile([.duration, .resistance])

        _ = routine.addExerciseInNewGroup(cross, context: context)
        #expect(routine.isCardio)
        #expect(routine.modality.primary == .elliptical)
    }

    @Test("A loaded carry tracks distance and is not cardio")
    func carryIsNotCardio() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "C")
        context.insert(routine)

        let handles = Equipment(name: "Farmers Walk Handles")
        context.insert(handles)
        let carry = Exercise(name: "Probe Carry", muscleGroup: .fullBody, exerciseType: .duration)
        context.insert(carry)
        carry.equipment = [handles]
        carry.metricProfile = MetricProfile([.weight, .distance, .duration])

        _ = routine.addExerciseInNewGroup(carry, context: context)
        // Load wins over distance — the other half of the old rule's error.
        #expect(!routine.isCardio)
    }

    @Test("A run plus a lifting block resolves to mixed, not to either one")
    func mixedRoutine() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let routine = Routine(name: "M")
        context.insert(routine)

        let run = Exercise(name: "Probe Run", muscleGroup: .fullBody, exerciseType: .duration)
        context.insert(run)
        run.metricProfile = MetricProfile([.distance, .duration, .pace], distanceUnit: .miles, isOutdoor: true)
        let press = Exercise(name: "Probe Press", muscleGroup: .chest)
        context.insert(press)

        _ = routine.addExerciseInNewGroup(run, context: context)
        _ = routine.addExerciseInNewGroup(press, context: context)

        #expect(!routine.isCardio)
        #expect(routine.modality.isMixed)
        #expect(routine.modality.primary == .strength)
    }
}

@Suite("Cardio findability")
struct CardioFindabilityTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self, RoutineExercise.self])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cardiofind-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("Typing a sport reaches its exercises, which no muscle word could")
    func searchReachesModality() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let run = Exercise(name: "Probe Jog", muscleGroup: .fullBody, exerciseType: .duration)
        context.insert(run)
        run.metricProfile = MetricProfile([.distance, .duration, .pace], distanceUnit: .miles, isOutdoor: true)

        let haystack = ExerciseFilterState.searchHaystack(run).lowercased()
        // The exercise is filed Full Body and named "Jog", so before this
        // neither "cardio" nor "run" reached it.
        #expect(haystack.contains("cardio"))
        #expect(haystack.contains("full body"))
    }

    @Test("The kind facet buckets every modality without a default")
    func kindBuckets() {
        #expect(CatalogKind(.running) == .cardio)
        #expect(CatalogKind(.rowing) == .cardio)
        #expect(CatalogKind(.elliptical) == .cardio)
        #expect(CatalogKind(.strength) == .strength)
        #expect(CatalogKind(.flexibility) == .mobility)
        // Exhaustive: a new family lands somewhere real, never nowhere.
        let bucketed = ExerciseModality.allCases.map(CatalogKind.init)
        #expect(bucketed.count == ExerciseModality.allCases.count)
    }

    @Test("Hiking and Indoor Cycling ship, with the right families")
    func newCatalogRows() throws {
        let hiking = try #require(SeedData.builtInProfile(named: "Hiking"))
        #expect(hiking.contains(.distance))
        #expect(hiking.isOutdoor)
        #expect(hiking.distanceUnit == .miles)

        let spin = try #require(SeedData.builtInProfile(named: "Indoor Cycling"))
        #expect(spin.contains(.power))
        #expect(spin.contains(.cadence))
        // A studio bike is indoors; the GPS layer must not engage.
        #expect(!spin.isOutdoor)
        // And it prescribes nothing: a duration default on a profile that
        // also tracks distance picks the driver behind your back, and a
        // class that runs long would count down to a number nobody chose.
        #expect(SeedData.builtInDefinition(named: "Indoor Cycling")?.defaultDurationSeconds == nil)
    }

    @Test("There is exactly one way to ride a bike indoors")
    func oneIndoorBikeRow() {
        // It shipped as two: a "Stationary Bike" exercise named after its own
        // equipment, and an "Indoor Cycling" added beside it. Same activity,
        // same machine, so the catalog was offering a choice with no answer
        // (Dave, build 158). The EQUIPMENT keeps its name — an exercise named
        // after its gear is the confusion, not the gear itself.
        #expect(SeedData.builtInDefinition(named: "Stationary Bike") == nil)
        #expect(SeedData.builtInDefinition(named: "Indoor Cycling") != nil)
        #expect(SeedData.builtInEquipment.contains { $0.name == "Stationary Bike" })
    }
}

/// The store side of that merge. Dropping a definition never removes a row
/// that already exists — `loadIfNeeded` only ever adds what is missing — so a
/// device seeded before build 158 keeps both rows unless something folds them.
@Suite("Indoor bike merge")
struct IndoorBikeMergeTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self,
            RoutineExercise.self, WorkoutSession.self, SetLog.self,
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("indoorbike-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeBuiltIn(_ name: String, in context: ModelContext) -> Exercise {
        let exercise = Exercise(name: name, muscleGroup: .fullBody)
        exercise.isBuiltIn = true
        context.insert(exercise)
        return exercise
    }

    private func exercises(_ context: ModelContext) -> [String] {
        ((try? context.fetch(FetchDescriptor<Exercise>())) ?? []).map(\.name).sorted()
    }

    @Test("The old row is RENAMED, so everything pointing at it comes along")
    func renamesInPlace() throws {
        let context = ModelContext(try makeContainer())
        let legacy = makeBuiltIn("Stationary Bike", in: context)
        let routine = Routine(name: "Probe Ride")
        context.insert(routine)
        let group = routine.addExerciseInNewGroup(legacy, context: context)

        SeedData.mergeIndoorBikeExercises(context: context)

        #expect(exercises(context) == ["Indoor Cycling"])
        // The same object, so the routine entry never dangled.
        #expect(group.sortedExercises.first?.exercise === legacy)
        #expect(legacy.metricProfile.contains(.cadence))
    }

    @Test("With both present, the unreferenced one goes")
    func dropsTheDuplicate() throws {
        let context = ModelContext(try makeContainer())
        let legacy = makeBuiltIn("Stationary Bike", in: context)
        _ = makeBuiltIn("Indoor Cycling", in: context)
        let routine = Routine(name: "Probe Ride")
        context.insert(routine)
        _ = routine.addExerciseInNewGroup(legacy, context: context)

        // The referenced row is the legacy one here, so IT is the survivor
        // and the freshly seeded duplicate is what goes.
        SeedData.mergeIndoorBikeExercises(context: context)
        #expect(exercises(context) == ["Indoor Cycling"])
        #expect(legacy.name == "Indoor Cycling")
    }

    @Test("A referenced pair is left alone rather than merged behind your back")
    func keepsBothWhenBothAreUsed() throws {
        let context = ModelContext(try makeContainer())
        let legacy = makeBuiltIn("Stationary Bike", in: context)
        let modern = makeBuiltIn("Indoor Cycling", in: context)
        let routine = Routine(name: "Probe Ride")
        context.insert(routine)
        _ = routine.addExerciseInNewGroup(legacy, context: context)
        _ = routine.addExerciseInNewGroup(modern, context: context)

        SeedData.mergeIndoorBikeExercises(context: context)
        // Both carry history; folding them would mean choosing whose logs
        // survive, which a launch pass has no business doing silently.
        #expect(exercises(context) == ["Indoor Cycling", "Stationary Bike"])
    }

    @Test("It is a no-op once there is nothing to merge")
    func idempotent() throws {
        let context = ModelContext(try makeContainer())
        _ = makeBuiltIn("Indoor Cycling", in: context)
        SeedData.mergeIndoorBikeExercises(context: context)
        SeedData.mergeIndoorBikeExercises(context: context)
        #expect(exercises(context) == ["Indoor Cycling"])
    }
}

@Suite("Quick start")
struct QuickStartTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self, RoutineExercise.self, WorkoutSession.self, SetLog.self])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quickstart-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("The pick list round-trips, and an empty one falls back")
    func picksCodec() {
        let raw = QuickStartPicks.raw(from: ["Running", "Indoor Cycling"])
        #expect(QuickStartPicks.names(from: raw) == ["Running", "Indoor Cycling"])
        // Never empty: an empty row would hide the "+" that is the only
        // way back to the editor.
        #expect(QuickStartPicks.names(from: "") == QuickStartPicks.fallback)
        // A name with a space survives — the separator is a unit separator,
        // not whitespace.
        #expect(QuickStartPicks.names(from: QuickStartPicks.raw(from: ["Open Water Swim"])) == ["Open Water Swim"])
    }

    @Test("Quick start is a scratch session with the block already in it")
    func startsAScratchSession() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // The REAL catalog row, not a probe: quick start prefills from the
        // exercise's own defaults, and `defaultSetCount` reads the catalog
        // by name (an unknown name gets the classic 3). A probe would
        // therefore have proved the opposite of what a run does.
        let def = try #require(SeedData.builtInDefinition(named: "Running"))
        let run = Exercise(name: def.name, muscleGroup: def.muscleGroup, exerciseType: def.exerciseType, isBuiltIn: true)
        context.insert(run)

        // What TodayView.startQuick does, in the same order.
        let session = WorkoutSession.startEmpty(context: context)
        let config = SessionExerciseConfig(exercise: run)
        let logs = session.appendExercise(config: config, context: context)

        // One effort, not three sets: a run is one continuous thing.
        #expect(logs.count == 1)
        #expect(session.sortedSetLogs.first?.exerciseName == "Running")
        // It is an ad-hoc session, so it graduates to a routine and
        // salvages on crash exactly like any other scratch workout.
        #expect(session.routine == nil)
        #expect(!session.isFinished)
    }
}

@Suite("The cardio hero")
struct CardioHeroCatalogTests {
    /// What the phone can read with no location fix.
    private let indoors: Set<WorkoutMetric> = [.duration]
    private let underGPS: Set<WorkoutMetric> = [.duration, .distance, .pace]

    private func profile(_ name: String) throws -> MetricProfile {
        try #require(SeedData.builtInProfile(named: name), "\(name) not in the catalog")
    }

    @Test("Quick-starting a run puts a clock on screen, not a dash")
    func quickStartedRunCountsUp() throws {
        // The exact shape quick start creates: the catalog row, no
        // prescription. `driver` falls back to distance (the first tracked
        // work metric), so before the hero chain this rendered a distance
        // card reading "—" with a Log key under it and nothing moving.
        let run = try profile("Running")
        let indoor = try #require(CardioHero.resolve(profile: run, target: { _ in nil }, measurable: indoors))
        #expect(indoor.hero == .elapsed)
        #expect(indoor.hero.isClock)

        // Outdoors with a fix, the distance climbing is the better hero.
        let outdoor = try #require(CardioHero.resolve(profile: run, target: { _ in nil }, measurable: underGPS))
        #expect(outdoor.hero == .measured(.distance))
    }

    @Test("A studio ride counts up rather than down from a number nobody chose")
    func studioRideCountsUp() throws {
        // Indoor Cycling ships open-ended deliberately (a class that runs
        // long must not stop at a preset), and its profile tracks distance
        // too, so it never reached the timer dock at all.
        let spin = try profile("Indoor Cycling")
        let r = try #require(CardioHero.resolve(profile: spin, target: { _ in nil }, measurable: indoors))
        #expect(r.hero == .elapsed)
        #expect(!r.hero.countsDown)
    }

    @Test("A prescribed hold still counts down, exactly as it did")
    func prescribedEffortsAreUnchanged() throws {
        // Side Plank is one of the catalog's authored 30 s holds, so this
        // is the unchanged path: a target exists, the clock can watch it,
        // the card counts down and logs itself at zero.
        let hold = try profile("Side Plank")
        let seconds = try #require(SeedData.builtInDefinition(named: "Side Plank")?.defaultDurationSeconds)
        let r = try #require(CardioHero.resolve(
            profile: hold,
            target: { $0 == .duration ? Double(seconds) : nil },
            measurable: indoors
        ))
        #expect(r.hero == .progress(metric: .duration, target: Double(seconds)))
        #expect(r.hero.countsDown)
    }

    @Test("Which exercises actually arrive untargeted, and which never do")
    func theFortyFiveSecondFloorDecidesWhoCountsUp() throws {
        // ⚠️ A duration-ONLY profile can never reach the count-up path in
        // practice, whatever its catalog row says. Plank authors no
        // default, but `Exercise.addTimeTargets` applies a 45 s floor to
        // any profile whose sole work metric is duration, so an ad-hoc
        // plank arrives prescribed and counts DOWN exactly as before.
        #expect(SeedData.builtInDefinition(named: "Plank")?.defaultDurationSeconds == nil)
        let plank = try profile("Plank")
        #expect(plank.metrics.filter(\.isWorkMetric) == [.duration])
        let prescribed = try #require(CardioHero.resolve(
            profile: plank, target: { $0 == .duration ? 45 : nil }, measurable: indoors
        ))
        #expect(prescribed.hero.countsDown)

        // The genuinely untargeted ones are the profiles with a SECOND
        // work metric, where the floor deliberately declines to fabricate
        // a duration: the ergs, the bikes, the loaded carries, the road.
        for name in ["Rowing", "Assault Bike", "Indoor Cycling", "Running"] {
            let open = try #require(CardioHero.resolve(
                profile: try profile(name), target: { _ in nil }, measurable: indoors
            ))
            #expect(open.hero == .elapsed, "\(name) should count up when nothing is prescribed")
        }
    }

    @Test("A prescribed erg piece keeps its stage rather than becoming a stopwatch")
    func prescribedErgKeepsTheStage() throws {
        // The console has the number; nothing was ever measuring it here,
        // so nothing degrades and nothing apologises.
        let erg = try profile("Rowing")
        let r = try #require(CardioHero.resolve(
            profile: erg, target: { $0 == .distance ? 500 : nil }, measurable: indoors
        ))
        #expect(r.hero == .selfReported(metric: .distance, target: 500))
        #expect(!r.hero.isClock)
        #expect(r.unmeasurableTarget == nil)
    }

    @Test("Every rep exercise in the catalog keeps its stage")
    func repWorkNeverGetsAClock() {
        // The gate that makes this whole change invisible to strength.
        for exercise in SeedData.makeBuiltInExercisesForTesting(equipment: []) {
            guard let profile = SeedData.builtInProfile(named: exercise.name), profile.tracksReps else { continue }
            let resolved = CardioHero.resolve(profile: profile, target: { _ in nil }, measurable: indoors)
            #expect(resolved == nil, "\(exercise.name) is rep work and must keep the stage")
        }
    }
}
