import Testing
@testable import WorkoutStore

/// Typing a number into the sheet.
@Suite("Plan typing")
struct PlanTypingTests {
    private static func committed(
        _ row: RoutineExercise,
        _ raw: String,
        into part: PlanPart,
        unit: WeightUnit = .pounds,
    ) -> ExercisePlan {
        var row = row
        row.commit(typed: raw, into: part, newWeightUnit: unit)
        return row.plan
    }

    @Test("A time's digits fill from the right")
    func timeFillsFromRight() throws {
        let pigeon = try RoutineExercise.builtIn("Pigeon stretch")
        #expect(pigeon.typedText("1", for: .target) == "0:01")
        #expect(pigeon.typedText("5", for: .target) == "0:05")
        #expect(pigeon.typedText("45", for: .target) == "0:45")
        #expect(pigeon.typedText("130", for: .target) == "1:30")
        #expect(pigeon.typedText("1234", for: .target) == "12:34")
        #expect(pigeon.typedText("", for: .target).isEmpty)
        #expect(Self.committed(pigeon, "130", into: .target).target == .time(seconds: 90))
        #expect(Self.committed(pigeon, "90", into: .target).target == .time(seconds: 90))
        #expect(Self.committed(pigeon, "5", into: .target).target == .time(seconds: 5))
        #expect(Self.committed(pigeon, "9959", into: .target).target == .time(seconds: 5999))
    }

    @Test("Over the digit limit is refused as it is typed")
    func digitLimits() throws {
        let pigeon = try RoutineExercise.builtIn("Pigeon stretch")
        #expect(pigeon.filtered("12345", for: .target) == "1234")
        #expect(pigeon.filtered("123", for: .sets) == "12")
        let pushUp = try RoutineExercise.builtIn("Push-up")
        #expect(pushUp.filtered("1234", for: .target) == "123")
        #expect(pushUp.filtered("1a2", for: .target) == "12")
        #expect(Self.committed(pushUp, "12", into: .sets).sets == 12)
        #expect(Self.committed(pushUp, "999", into: .target).target == .reps(999))
    }

    @Test("A weight takes one separator, dot or comma, and two decimals")
    func weightText() throws {
        let row = try RoutineExercise.builtIn("Goblet squat")
        #expect(row.filtered("142.5", for: .weight) == "142.5")
        #expect(row.filtered("142,5", for: .weight) == "142,5")
        #expect(row.filtered("1.2.3", for: .weight) == "1.23")
        #expect(row.filtered("1.234", for: .weight) == "1.23")
        #expect(row.filtered("123456", for: .weight) == "1234")
        #expect(Self.committed(row, "142.5", into: .weight).weight == Weight(142.5, .pounds))
        #expect(Self.committed(row, "142,5", into: .weight).weight == Weight(142.5, .pounds))
        #expect(Self.committed(row, "20", into: .weight, unit: .kilograms).weight
            == Weight(20, .kilograms))
    }

    @Test("A typed weight keeps the unit it had")
    func weightKeepsUnit() throws {
        let row = try RoutineExercise.builtIn("Goblet squat") { $0.weight = Weight(16, .kilograms) }
        #expect(Self.committed(row, "20", into: .weight, unit: .pounds).weight
            == Weight(20, .kilograms))
    }

    @Test("Empty or zero keeps sets, reps, and time, and makes a weight not set")
    func emptyOrZero() throws {
        let row = try RoutineExercise.builtIn("Goblet squat") { $0.weight = Weight(35, .pounds) }
        #expect(Self.committed(row, "", into: .sets) == row.plan)
        #expect(Self.committed(row, "0", into: .sets) == row.plan)
        #expect(Self.committed(row, "00", into: .target) == row.plan)
        #expect(Self.committed(row, "", into: .weight).weight == nil)
        #expect(Self.committed(row, "0.0", into: .weight).weight == nil)
        let pigeon = try RoutineExercise.builtIn("Pigeon stretch")
        #expect(Self.committed(pigeon, "000", into: .target) == pigeon.plan)
    }
}
