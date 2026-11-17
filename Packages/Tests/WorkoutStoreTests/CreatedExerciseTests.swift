import Foundation
import Testing
@testable import WorkoutStore

/// What a created exercise works as, from the five settings it was made with.
@Suite("Created exercises")
struct CreatedExerciseTests {
    private static func exercise(
        _ group: MuscleGroup = .back,
        _ equipment: Set<Equipment> = [],
        _ measure: Measure = .reps,
        perSide: Bool = false,
        name: String = "Made up",
    ) -> Exercise {
        exercise([group], equipment, measure, perSide: perSide, name: name)
    }

    private static func exercise(
        _ groups: Set<MuscleGroup>,
        _ equipment: Set<Equipment> = [],
        _ measure: Measure = .reps,
        perSide: Bool = false,
        name: String = "Made up",
    ) -> Exercise {
        Exercise(created: CreatedExercise(
            name: name,
            muscleGroups: groups,
            equipment: equipment,
            measure: measure,
            isPerSide: perSide,
        ))
    }

    @Test("Its load follows its equipment and Per side, the first weighted piece winning")
    func load() {
        #expect(Self.exercise(.legs, [.barbell]).load == .bar)
        #expect(Self.exercise(.arms, [.dumbbells]).load == .pair)
        #expect(Self.exercise(.shoulders, [.dumbbells], perSide: true).load == .single)
        #expect(Self.exercise(.legs, [.kettlebell]).load == .single)
        #expect(Self.exercise(.core, [.medicineBall]).load == .single)
        for piece in [Equipment.rings, .band, .bench, .pullUpBar, .balanceBoard] {
            #expect(Self.exercise(.back, [piece]).load == nil, "\(piece)")
        }
        #expect(Self.exercise(.back).load == nil)
        // Barbell, dumbbells, kettlebell, medicine ball: the first one held decides.
        #expect(Self.exercise(.legs, [.kettlebell, .barbell]).load == .bar)
        #expect(Self.exercise(.legs, [.kettlebell, .dumbbells]).load == .pair)
        #expect(Self.exercise(.back, [.dumbbells, .bench]).load == .pair)
    }

    @Test("It starts where the lightest built-in of its piece starts, a bar at the empty bar")
    func startingWeight() throws {
        for piece in [Equipment.dumbbells, .kettlebell, .medicineBall] {
            let builtIns = Exercise.builtIn.filter { $0.equipment == [piece] && $0.load != nil }
            for unit in [WeightUnit.pounds, .kilograms] {
                let starts = builtIns.compactMap { $0.startingWeight(in: unit)?.amount }
                let lightest = try #require(starts.min())
                let created = Self.exercise(.arms, [piece]).startingWeight(in: unit)
                #expect(created == Weight(lightest, unit), "\(piece) in \(unit)")
            }
        }
        #expect(Self.exercise(.legs, [.barbell]).startingWeight(in: .pounds) == Weight(45, .pounds))
        #expect(Self.exercise(.back, [.rings]).startingWeight(in: .pounds) == nil)
    }

    @Test("It starts at 3 × 10 reps, or 3 × 30 s")
    func plan() {
        let reps = Self.exercise(.back, [.rings]).defaultPlan(in: .pounds)
        #expect(reps == ExercisePlan(sets: 3, target: .reps(10)))
        let time = Self.exercise(.core, [], .time).defaultPlan(in: .pounds)
        #expect(time == ExercisePlan(sets: 3, target: .time(seconds: 30)))
    }

    @Test("Its automatic rest follows its muscle group, one step shorter with no weight")
    func rest() {
        // Back, an upper-body compound, 90 s at 10 reps; no weight, one step shorter.
        #expect(Self.exercise(.back, [.rings]).defaultRest(for: .reps(10)) == 60)
        #expect(Self.exercise(.back, [.dumbbells]).defaultRest(for: .reps(10)) == 90)
        #expect(Self.exercise(.legs, [.barbell]).defaultRest(for: .reps(10)) == 120)
        #expect(Self.exercise(.chest, [.barbell]).defaultRest(for: .reps(5)) == 150)
        #expect(Self.exercise(.arms, [.dumbbells]).defaultRest(for: .reps(10)) == 60)
        #expect(Self.exercise(.core, [.medicineBall]).defaultRest(for: .reps(10)) == 60)
        #expect(Self.exercise(.core).defaultRest(for: .reps(10)) == 45)
    }

    @Test("With several groups it rests as the longest-resting: legs, then chest, back, shoulders")
    func restOfSeveralGroups() {
        let weighted: Set<Equipment> = [.dumbbells]
        // Any legs: a lower-body compound, 120 s at 10 reps.
        #expect(Self.exercise([.arms, .legs], weighted).defaultRest(for: .reps(10)) == 120)
        #expect(Self.exercise([.shoulders, .legs, .core], weighted).defaultRest(for: .reps(10))
            == 120)
        // Else any upper-body group: 90 s.
        #expect(Self.exercise([.arms, .back], weighted).defaultRest(for: .reps(10)) == 90)
        #expect(Self.exercise([.core, .chest], weighted).defaultRest(for: .reps(10)) == 90)
        // Else single-joint: 60 s.
        #expect(Self.exercise([.arms, .core], weighted).defaultRest(for: .reps(10)) == 60)
        // No weight, one step shorter, as for one group.
        #expect(Self.exercise([.back, .shoulders], [.rings]).defaultRest(for: .reps(10)) == 60)
        #expect(Self.exercise([.legs, .core]).defaultRest(for: .reps(10)) == 90)
    }

    @Test("Add needs a new name and at least one muscle group")
    func canAdd() {
        let list = ExerciseList.builtIn
        #expect(CreatedExercise.canAdd(
            named: "Ring row with rotation",
            muscleGroups: [.back],
            to: list,
        ))
        #expect(CreatedExercise.canAdd(
            named: "Ring row with rotation",
            muscleGroups: [.back, .shoulders],
            to: list,
        ))
        #expect(!CreatedExercise.canAdd(
            named: "Ring row with rotation",
            muscleGroups: [],
            to: list,
        ))
        #expect(!CreatedExercise.canAdd(named: "  ", muscleGroups: [.back], to: list))
        #expect(!CreatedExercise.canAdd(named: "pull up", muscleGroups: [.back], to: list))
    }

    @Test("Every checked group counts toward the name; each counts the exercise once")
    func namingSeveralGroups() {
        let namer = RoutineNamer.muscleGroupsOnly
        let id = UUID()
        // One exercise, Back and Shoulders: both named.
        let backAndShoulders = [Self.exercise([.back, .shoulders], name: "One")]
        #expect(namer.name(for: backAndShoulders, of: id) == "Back and shoulders")
        #expect(RoutineFocus(of: backAndShoulders) == .upperBody)
        // Back and Shoulders, then Back alone: back works in both, three in five, a back focus.
        let mostlyBack = backAndShoulders + [Self.exercise(.back, name: "Two")]
        #expect(RoutineFocus(of: mostlyBack) == .group(.back))
        // Legs and Core with Shoulders: three groups, full body.
        let spread = [
            Self.exercise([.legs, .core], name: "One"),
            Self.exercise(.shoulders, name: "Two"),
        ]
        #expect(namer.name(for: spread, of: id) == "Full body")
        #expect(RoutineFocus(of: spread) == .fullBody)
        // Legs and Core alone: a pair.
        let legsAndCore = [Self.exercise([.legs, .core], name: "One")]
        #expect(RoutineFocus(of: legsAndCore) == .pair(.legs, .core))
        #expect(namer.name(for: legsAndCore, of: id) == "Legs and core")
    }

    @Test("A superset with a created exercise of several groups shares a muscle by any one")
    func roundRestOfSeveralGroups() throws {
        let made = Self.exercise([.shoulders, .back], [.dumbbells])
        var routine = try Routine(exercises: [
            RoutineExercise(exercise: made, weightUnit: .pounds),
            RoutineExercise.builtIn("Dumbbell row"),
        ])
        routine.join(routine.exercises[0].id, .below)
        // Back in common: the full 90 s, not 30.
        #expect(routine.restAfterRound(of: routine.exercises[0].id) == 90)
    }

    @Test("Muscle groups read as a line from a set, in body order")
    func muscleGroupLine() {
        #expect(Set([MuscleGroup.shoulders, .back]).line == "Back, shoulders")
        #expect(Set([MuscleGroup.core]).line == "Core")
        #expect(Set<MuscleGroup>().line == nil)
    }

    @Test("A routine of created exercises is named for their groups, never a push or pull focus")
    func naming() {
        let rows = [
            Self.exercise(.back, [.rings], name: "One"),
            Self.exercise(.back, [.dumbbells], name: "Two"),
            Self.exercise(.chest, [.dumbbells], name: "Three"),
        ]
        #expect(RoutineFocus(of: rows) == .group(.back))
        // Upper body with no movement claimed: neither a push nor a pull day.
        let pushes = [Self.exercise(.chest, name: "One"), Self.exercise(.shoulders, name: "Two")]
        #expect(RoutineFocus(of: pushes) == .upperBody)
        #expect(RoutineNamer.muscleGroupsOnly.name(for: rows, of: UUID()) == "Chest and back")
    }

    @Test("Equipment reads as a line from a set, nothing for none")
    func equipmentLine() {
        #expect(Set([Equipment.rings]).line == "Rings")
        #expect(Set([Equipment.bench, .dumbbells]).line == "Dumbbells, bench")
        #expect(Set<Equipment>().line == nil)
        #expect(Self.exercise(.back, [.dumbbells, .bench]).equipmentLine == "Dumbbells, bench")
    }

    @Test("A superset with a created exercise shares a muscle by its group")
    func roundRest() throws {
        let made = Self.exercise(.back, [.dumbbells])
        let row = try RoutineExercise.builtIn("Dumbbell row")
        var routine = Routine(exercises: [
            RoutineExercise(exercise: made, weightUnit: .pounds),
            row,
        ])
        routine.join(routine.exercises[0].id, .below)
        // Both back, 90 s each: the full 90 s, not 30.
        #expect(routine.restAfterRound(of: routine.exercises[0].id) == 90)
        var apart = Routine(exercises: [
            RoutineExercise(exercise: Self.exercise(.legs, [.dumbbells]), weightUnit: .pounds),
            row,
        ])
        apart.join(apart.exercises[0].id, .below)
        #expect(apart.restAfterRound(of: apart.exercises[0].id) == 60)
    }

    @Test("The list is built-ins and created exercises A to Z; ids never collide")
    func list() {
        let created = CreatedExercise(name: "Ring row with rotation", muscleGroups: [.back])
        let list = ExerciseList(created: [created])
        let names = list.all.map(\.name)
        #expect(names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        #expect(list.exercise(id: created.id)?.name == "Ring row with rotation")
        #expect(list.all.count == Exercise.builtIn.count + 1)
        #expect(created.id.hasPrefix("created:"))
        #expect(Exercise.builtIn.allSatisfy { !$0.id.contains(":") })
        #expect(ExerciseList.builtIn.adding(created) == list)
    }

    @Test("Create is offered for a search with no exact name, by the search's folding")
    func offersCreate() {
        let list = ExerciseList.builtIn
        #expect(list.offersCreate(for: "Ring"))
        #expect(list.offersCreate(for: "Ring row with rotation"))
        #expect(!list.offersCreate(for: "ring dip"))
        #expect(!list.offersCreate(for: "RING-DIP"))
        #expect(!list.offersCreate(for: "pull up"))
        #expect(!list.offersCreate(for: ""))
        #expect(!list.offersCreate(for: "  "))
        let made = list.adding(CreatedExercise(
            name: "Ring row with rotation",
            muscleGroups: [.back],
        ))
        #expect(!made.offersCreate(for: "ring row with rotation "))
        // A name with no letters or digits is taken once, compared whole.
        let flexed = list.adding(CreatedExercise(name: "💪", muscleGroups: [.arms]))
        #expect(list.offersCreate(for: "💪"))
        #expect(!flexed.offersCreate(for: " 💪"))
        #expect(flexed.offersCreate(for: "💪💪"))
    }
}
