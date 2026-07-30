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
}
