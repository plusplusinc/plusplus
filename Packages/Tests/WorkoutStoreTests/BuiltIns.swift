import Testing
@testable import WorkoutStore

extension Exercise {
    /// The built-in exercise named `name`; a failed requirement when there is none.
    static func builtIn(named name: String) throws -> Exercise {
        try #require(builtIn.first { $0.name == name }, "No built-in named \(name)")
    }

    /// The built-in exercises named, in order.
    static func builtIn(named names: [String]) throws -> [Exercise] {
        try names.map(builtIn(named:))
    }
}

extension RoutineExercise {
    /// A row of the built-in exercise named `name`, its default plan changed by `edit`.
    static func builtIn(
        _ name: String,
        _ edit: (inout ExercisePlan) -> Void = { _ in },
    ) throws -> RoutineExercise {
        let exercise = try Exercise.builtIn(named: name)
        var plan = exercise.defaultPlan(in: .pounds)
        edit(&plan)
        return RoutineExercise(exercise: exercise, plan: plan)
    }
}
