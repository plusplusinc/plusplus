import Testing
@testable import WorkoutStore

/// A built-in's customization as a value: what it keeps, what it derives, what it leaves as
/// shipped, and how it reads in the exercise list.
@Suite("Customization")
struct CustomizationTests {
    private static func bench() throws -> Exercise {
        try #require(Exercise.builtIn(id: "barbell-bench-press"))
    }

    /// Bench press with `change` made to its settings.
    private static func customized(
        _ change: (inout ExerciseSettings) -> Void,
    ) throws -> Exercise {
        let bench = try bench()
        var settings = bench.settings
        change(&settings)
        return Exercise(builtIn: bench, customized: Customization(of: bench, to: settings))
    }

    @Test("A customization keeps only what differs from the original")
    func keepsOnlyChanges() throws {
        let bench = try Self.bench()
        var settings = bench.settings
        settings.muscleGroups = [.chest, .arms]
        settings.isPerSide = true
        #expect(Customization(of: bench, to: settings).changed == [.muscleGroups, .perSide])
        settings.isPerSide = false
        #expect(Customization(of: bench, to: settings).changed == [.muscleGroups])
        settings.muscleGroups = [.chest]
        #expect(Customization(of: bench, to: settings).isEmpty)

        // In the list, one set back to how it shipped is no customization at all.
        let list = ExerciseList.builtIn.customizing(bench.id, to: bench.settings)
        #expect(list.customization(id: bench.id) == nil)
        #expect(list == .builtIn)
    }

    @Test("A customized built-in rests by its kind of lift, whatever its groups")
    func restsByKindOfLift() throws {
        let bench = try Self.bench()
        for groups: Set<MuscleGroup> in [[.chest, .arms], [.legs], [.core], []] {
            let exercise = try Self.customized { $0.muscleGroups = groups }
            for target: SetTarget in [.reps(5), .reps(12), .time(seconds: 30)] {
                #expect(exercise.defaultRest(for: target) == bench.defaultRest(for: target))
            }
        }
    }

    @Test("Its load is the original's until equipment or Per side changes, then a created one's")
    func loadFollowsEquipment() throws {
        let bench = try Self.bench()
        #expect(try Self.customized { $0.name = "Bench press" }.load == .bar)
        let dumbbells = try Self.customized { $0.equipment = [.dumbbells, .bench] }
        #expect(dumbbells.load == .pair)
        #expect(dumbbells.startsAt == Equipment.dumbbells.lightStart)
        let perSide = try Self.customized {
            $0.equipment = [.dumbbells, .bench]
            $0.isPerSide = true
        }
        #expect(perSide.load == .single)
        #expect(try Self.customized { $0.equipment = [] }.load == nil)
        let back = try Self.customized { $0.equipment = bench.equipment }
        #expect(back.load == .bar)
        #expect(back.defaultPlan(in: .pounds) == bench.defaultPlan(in: .pounds))
    }

    @Test("Adding kit that holds no weight keeps the shipped load and start")
    func benchKeepsLoad() throws {
        let triceps = try #require(Exercise.builtIn(id: "triceps-extension"))
        var settings = triceps.settings
        settings.equipment.insert(.bench)
        let customized = Exercise(
            builtIn: triceps,
            customized: Customization(of: triceps, to: settings),
        )
        #expect(customized.load == .single)
        #expect(customized.defaultPlan(in: .pounds) == triceps.defaultPlan(in: .pounds))
    }

    @Test("Its plan is the original's until its measure changes, then a created one's")
    func planFollowsMeasure() throws {
        let bench = try Self.bench()
        let timed = try Self.customized { $0.measure = .time }
        #expect(timed.defaultPlan(in: .pounds).sets == 3)
        #expect(timed.defaultPlan(in: .pounds).target == .time(seconds: 30))
        let back = try Self.customized { $0.measure = .reps }
        #expect(back.defaultPlan(in: .pounds) == bench.defaultPlan(in: .pounds))
    }

    @Test("A setting nobody changed follows the catalog, so an app update still reaches it")
    func unchangedFollowsCatalog() throws {
        let bench = try Self.bench()
        // Settings that disagree with the catalog everywhere, but only groups marked changed,
        // as a customization saved before an update changed the built-in reads after it.
        let stale = Customization(
            exerciseID: bench.id,
            settings: ExerciseSettings(
                name: "Old name",
                muscleGroups: [.chest, .arms],
                equipment: [.kettlebell],
                measure: .time,
                isPerSide: true,
            ),
            changed: [.muscleGroups],
        )
        let exercise = Exercise(builtIn: bench, customized: stale)
        #expect(exercise.muscleGroups == [.chest, .arms])
        #expect(exercise.name == bench.name)
        #expect(exercise.equipment == bench.equipment)
        #expect(exercise.isPerSide == bench.isPerSide)
        #expect(exercise.defaultPlan(in: .pounds) == bench.defaultPlan(in: .pounds))
    }

    @Test("A customized built-in keeps its tags, so a routine still names it for its movement")
    func keepsTags() throws {
        let bench = try Self.bench()
        let exercise = try Self.customized {
            $0.name = "Bench press"
            $0.muscleGroups = [.arms]
        }
        #expect(exercise.tags == bench.tags)
    }

    @Test("What changed reads in the form's order")
    func changesText() throws {
        let original = try Self.bench().settings
        var settings = original
        #expect(settings.changes(from: original).isEmpty)
        settings.muscleGroups.insert(.arms)
        #expect(settings.changes(from: original) == ["Arms added"])
        settings.name = "Bench press"
        settings.muscleGroups = [.arms]
        settings.equipment = [.dumbbells, .bench]
        settings.measure = .time
        settings.isPerSide = true
        #expect(settings.changes(from: original) == [
            "Renamed from Barbell bench press",
            "Chest removed",
            "Arms added",
            "Dumbbells added",
            "Barbell removed",
            "Timed",
            "Per side",
        ])
    }

    @Test("Clearing returns exactly what shipped")
    func clearingReturnsShipped() throws {
        let bench = try Self.bench()
        var settings = bench.settings
        settings.name = "Bench press"
        settings.equipment = []
        let list = ExerciseList.builtIn.customizing(bench.id, to: settings)
        #expect(list.exercise(id: bench.id)?.name == "Bench press")
        #expect(list.original(id: bench.id) == bench)
        let cleared = list.clearingCustomizations(bench.id)
        #expect(cleared == .builtIn)
        #expect(cleared.exercise(id: bench.id) == bench)
    }

    @Test("A renamed built-in's shipped name stays taken, but for itself")
    func renamedKeepsShippedName() throws {
        let bench = try Self.bench()
        var settings = bench.settings
        settings.name = "Bench press"
        let list = ExerciseList.builtIn.customizing(bench.id, to: settings)
        #expect(list.hasExercise(named: "barbell bench press", besides: "created:other"))
        #expect(!list.hasExercise(named: "Barbell bench press", besides: bench.id))
        #expect(list.hasExercise(named: "Bench press"))
    }

    @Test("A customization of no built-in, or of nothing, reads as none")
    func strayCustomizationsIgnored() throws {
        let bench = try Self.bench()
        let list = ExerciseList(created: [], customizations: [
            Customization(
                exerciseID: "no-such-exercise",
                settings: bench.settings,
                changed: [.name],
            ),
            Customization(exerciseID: bench.id, settings: bench.settings, changed: []),
        ])
        #expect(list == .builtIn)
    }
}
