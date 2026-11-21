import Testing
@testable import WorkoutStore

/// What Delete asks before a created exercise goes: the open workout named first when it uses
/// the exercise, the others counted after it; otherwise every workout counted, as before.
@Suite("Delete's question")
struct DeleteQuestionTests {
    private static let history = " Deleting doesn’t affect your workout history."

    @Test(
        "The open workout is named first when it uses the exercise",
        arguments: [
            (1, "It will be removed from this workout."),
            (2, "It will be removed from this workout and 1 other."),
            (4, "It will be removed from this workout and 3 others."),
        ],
    )
    func namesOpenWorkout(workoutCount: Int, workouts: String) {
        #expect(
            DeleteQuestion.message(workoutCount: workoutCount, usedByOpenWorkout: true)
                == workouts + Self.history,
        )
    }

    @Test(
        "Workouts are counted when the open one doesn't use the exercise",
        arguments: [
            (0, "No workout uses it."),
            (1, "It will be removed from the workout that uses it."),
            (3, "It will be removed from the 3 workouts that use it."),
        ],
    )
    func countsOtherWorkouts(workoutCount: Int, workouts: String) {
        #expect(
            DeleteQuestion.message(workoutCount: workoutCount, usedByOpenWorkout: false)
                == workouts + Self.history,
        )
    }
}
