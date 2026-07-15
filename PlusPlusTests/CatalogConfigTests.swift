import Foundation
import Testing
import SwiftData
import PlusPlusKit
@testable import PlusPlus

/// Add-time config defaults (catalog audit, 2026-07-15): per-exercise
/// set counts and rep/duration prescriptions in the definitions table,
/// the duration floor for timed-work profiles, and the heart-rate row
/// gating for stretches and static holds.
@Suite("Catalog add-time config")
struct CatalogConfigTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self, Equipment.self, EquipmentLibrary.self, Routine.self, ExerciseGroup.self,
            RoutineExercise.self, WorkoutSession.self, SetLog.self,
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-config-\(UUID().uuidString).store")
        let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// A catalog exercise as the seeder would create it (equipment-free
    /// fixtures — the name keys every table lookup).
    private func builtIn(_ name: String) throws -> Exercise {
        let def = try #require(SeedData.builtInDefinition(named: name), "\(name) not in the catalog")
        return Exercise(name: def.name, muscleGroup: def.muscleGroup, exerciseType: def.exerciseType, isBuiltIn: true)
    }

    @Test("The audit's key table assignments hold")
    func keyAssignments() throws {
        // Static stretches: one 30 s hold — matching the Full Body
        // Stretch routine's existing 1×30 prescription.
        for name in ["Standing Hamstring Stretch", "Pigeon Pose", "Child's Pose", "Downward Dog"] {
            let def = try #require(SeedData.builtInDefinition(named: name))
            #expect(def.defaultSets == 1, "\(name) should land as a single hold")
            #expect(def.defaultDurationSeconds == 30, "\(name) should hold 30 s")
        }
        // Dynamic mobility: one pass.
        for name in ["Arm Circles", "Cat-Cow", "World's Greatest Stretch", "Inchworm"] {
            #expect(SeedData.builtInDefinition(named: name)?.defaultSets == 1)
        }
        // Steady cardio: one piece. Distance/calorie machines take no
        // fabricated targets; duration-only consoles get an honest
        // 10-minute piece (the 45 s work-metric floor would be absurd).
        for name in ["Running", "Walking", "Cycling", "Rowing", "Treadmill Run", "Ski Erg", "Ruck"] {
            #expect(SeedData.builtInDefinition(named: name)?.defaultSets == 1, "\(name) should default to one piece")
        }
        for name in ["Elliptical", "Stair Climber", "Vertical Climber", "Upper Body Ergometer"] {
            let def = SeedData.builtInDefinition(named: name)
            #expect(def?.defaultSets == 1, "\(name) should default to one piece")
            #expect(def?.defaultDurationSeconds == 600, "\(name) should default to a 10-minute piece")
        }
        // Technical / max-effort rep prescriptions.
        #expect(SeedData.builtInDefinition(named: "Turkish Get-Up")?.defaultReps == 3)
        #expect(SeedData.builtInDefinition(named: "Power Clean")?.defaultReps == 3)
        #expect(SeedData.builtInDefinition(named: "Nordic Curl")?.defaultReps == 5)
        #expect(SeedData.builtInDefinition(named: "Rope Climb")?.defaultReps == 3)
        // Round/hold lengths that the 45 s floor got wrong.
        #expect(SeedData.builtInDefinition(named: "Heavy Bag Rounds")?.defaultDurationSeconds == 180)
        #expect(SeedData.builtInDefinition(named: "Parallette L-Sit")?.defaultDurationSeconds == 20)
        #expect(SeedData.builtInDefinition(named: "Side Plank")?.defaultDurationSeconds == 30)
        // The classic strength block is untouched.
        let bench = try #require(SeedData.builtInDefinition(named: "Bench Press"))
        #expect(bench.defaultSets == 3)
        #expect(bench.defaultReps == nil)
        #expect(bench.defaultDurationSeconds == nil)
    }

    @Test("Every catalog default is coherent with its profile and the steppers")
    func tableCoherence() {
        for exercise in SeedData.makeBuiltInExercisesForTesting(equipment: []) {
            guard let def = SeedData.builtInDefinition(named: exercise.name),
                  let profile = SeedData.builtInProfile(named: exercise.name) else {
                Issue.record("no definition/profile for \(exercise.name)")
                continue
            }
            // The Sets stepper clamps 1...20; a default outside it would
            // be unreachable state.
            #expect((1...20).contains(def.defaultSets), "\(exercise.name) defaultSets out of range")
            if let reps = def.defaultReps {
                #expect(profile.tracksReps, "\(exercise.name) has a rep default but doesn't track reps")
                #expect(WorkoutMetric.reps.range.contains(Double(reps)), "\(exercise.name) rep default out of range")
            }
            if let seconds = def.defaultDurationSeconds {
                #expect(profile.contains(.duration), "\(exercise.name) has a duration default but doesn't track duration")
                #expect(WorkoutMetric.duration.range.contains(Double(seconds)), "\(exercise.name) duration default out of range")
                // Driver-hijack guard: a catalog duration prescription on
                // a profile with another work metric (a rower's distance)
                // would silently flip fresh entries into timer mode.
                #expect(profile.metrics.filter(\.isWorkMetric) == [.duration],
                        "\(exercise.name) has a duration default but duration isn't its sole work metric")
            }
            // The HR column only means something on the duration family —
            // a reps-legacy exercise never shows the row anyway, so a
            // false there would be dead config hiding a real intent.
            if !def.supportsHeartRate {
                #expect(profile.legacyType == .duration || def.defaultSets == 1,
                        "\(exercise.name) drops the HR row but isn't a timed hold or a mobility pass")
            }
        }
    }

    @Test("Adding a stretch lands as one 30 s hold; strength keeps the classic block")
    func addTimeDefaults() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stretch = try builtIn("Pigeon Pose")
        context.insert(stretch)
        let bench = try builtIn("Bench Press")
        context.insert(bench)

        let routine = Routine(name: "Probe Mix")
        context.insert(routine)

        let stretchGroup = routine.addExerciseInNewGroup(stretch, context: context)
        #expect(stretchGroup.sets == 1)
        let stretchEntry = try #require(stretchGroup.sortedExercises.first)
        #expect(stretchEntry.durationSeconds == 30)
        #expect(stretchEntry.reps == nil)

        let benchGroup = routine.addExerciseInNewGroup(bench, context: context)
        #expect(benchGroup.sets == 3)
        let benchEntry = try #require(benchGroup.sortedExercises.first)
        #expect(benchEntry.reps == 10)
    }

    @Test("Steady cardio adds one piece and still takes no fabricated target")
    func cardioAddDefaults() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let erg = try builtIn("Rowing")
        context.insert(erg)
        let routine = Routine(name: "Probe Cardio")
        context.insert(routine)

        let group = routine.addExerciseInNewGroup(erg, context: context)
        #expect(group.sets == 1)
        let entry = try #require(group.sortedExercises.first)
        // The driver-hijack rule holds: distance-first profiles start
        // target-less, never with an invented 45 s timer.
        #expect(entry.durationSeconds == nil)
        #expect(entry.extraTargets.isEmpty)
    }

    @Test("A loaded carry starts with a startable duration target")
    func carryDurationFloor() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Built-in: [weight, duration] via the seed table.
        let carry = try builtIn("Farmer's Carry")
        context.insert(carry)
        // Custom with the same shape — the floor is a profile rule, not
        // a catalog one.
        let probe = Exercise(name: "Probe Carry", muscleGroup: .core, exerciseType: .duration)
        context.insert(probe)
        probe.metricProfile = MetricProfile([.weight, .duration])

        let routine = Routine(name: "Probe Carries")
        context.insert(routine)
        let carryEntry = try #require(routine.addExerciseInNewGroup(carry, context: context).sortedExercises.first)
        let probeEntry = try #require(routine.addExerciseInNewGroup(probe, context: context).sortedExercises.first)

        // Duration is the only WORK metric, so the 45 s floor applies —
        // these used to start with no work target at all.
        #expect(carryEntry.durationSeconds == 45)
        #expect(probeEntry.durationSeconds == 45)
    }

    @Test("Catalog rep prescriptions prefill, and a bumped default still wins")
    func repPrescriptionPrecedence() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let getUp = try builtIn("Turkish Get-Up")
        context.insert(getUp)
        let routine = Routine(name: "Probe Prescriptions")
        context.insert(routine)

        let first = try #require(routine.addExerciseInNewGroup(getUp, context: context).sortedExercises.first)
        #expect(first.reps == 3)

        // #187: the user's latest word beats the catalog.
        getUp.defaultReps = 5
        let second = try #require(routine.addExerciseInNewGroup(getUp, context: context).sortedExercises.first)
        #expect(second.reps == 5)

        let stretch = try builtIn("Pigeon Pose")
        context.insert(stretch)
        stretch.defaultDurationSeconds = 60
        let entry = try #require(routine.addExerciseInNewGroup(stretch, context: context).sortedExercises.first)
        #expect(entry.durationSeconds == 60)
    }

    @Test("Session add-sheet configs mirror the routine defaults")
    func sessionConfigDefaults() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stretch = try builtIn("Child's Pose")
        context.insert(stretch)
        let bench = try builtIn("Bench Press")
        context.insert(bench)

        let stretchConfig = SessionExerciseConfig(exercise: stretch)
        #expect(stretchConfig.sets == 1)
        #expect(stretchConfig.durationSeconds == 30)

        let benchConfig = SessionExerciseConfig(exercise: bench)
        #expect(benchConfig.sets == 3)
        #expect(benchConfig.reps == 10)

        // An explicit count still wins over the exercise default.
        #expect(SessionExerciseConfig(exercise: stretch, sets: 4).sets == 4)
    }

    @Test("Heart-rate prescription gating: stretches drop it, conditioning keeps it")
    func heartRateGating() throws {
        #expect(try builtIn("Pigeon Pose").supportsHeartRateTarget == false)
        #expect(try builtIn("Plank").supportsHeartRateTarget == false)
        #expect(try builtIn("Wall Sit").supportsHeartRateTarget == false)
        #expect(try builtIn("Running").supportsHeartRateTarget == true)
        #expect(try builtIn("Farmer's Carry").supportsHeartRateTarget == true)
        // Customs always keep the row — intent can't be classified.
        let custom = Exercise(name: "Probe Hold", muscleGroup: .core, exerciseType: .duration)
        #expect(custom.supportsHeartRateTarget)

        // The sheets' shared row gate: dropped for a stretch, restored by
        // the stale-target escape, present for cardio, absent for reps
        // work regardless of the column.
        let stretch = try builtIn("Pigeon Pose")
        #expect(!stretch.showsHeartRateTargetRow(existingTarget: nil))
        #expect(stretch.showsHeartRateTargetRow(existingTarget: .zone(.zone2)))
        #expect(try builtIn("Running").showsHeartRateTargetRow(existingTarget: nil))
        #expect(try !builtIn("Bench Press").showsHeartRateTargetRow(existingTarget: nil))
    }
}
