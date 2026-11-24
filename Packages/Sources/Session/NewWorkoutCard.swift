import WorkoutStore

/// The card on a new workout New made from the Workouts list's Muscle and Equipment filters
/// (`AppSession.startNew(from:)`): those filters' words, and the first exercises Add exercise
/// lists for them, in its order, each to tap to add. A tapped one leaves and nothing takes its
/// place; the card goes once the last is used or it is closed, for good on that workout. Not
/// stored: it lasts while that workout stays open in the app.
public struct NewWorkoutCard: Equatable, Sendable {
    /// How many exercises the card offers at most.
    static let count = 4

    public let workout: Workout.ID
    /// The chosen filters as their buttons read them: "Legs", "Dumbbells".
    public let filterWords: [String]
    public private(set) var exercises: [Exercise]

    /// Nil with no Muscle or Equipment filter chosen, or none of the exercises passing them.
    init?(workout: Workout.ID, filter: ExerciseFilter, exercises list: ExerciseList) {
        guard !filter.muscleGroups.isEmpty || !filter.equipment.isEmpty else { return nil }
        let matches = list.filtered(by: filter, matching: "").matches.prefix(Self.count)
        guard !matches.isEmpty else { return nil }
        self.workout = workout
        filterWords = [filter.muscleLabel, filter.equipmentLabel].compactMap(\.self)
        exercises = Array(matches)
    }

    /// Takes `id` off the card: nil once it was the last.
    func using(_ id: Exercise.ID) -> Self? {
        var card = self
        card.exercises.removeAll { $0.id == id }
        return card.exercises.isEmpty ? nil : card
    }
}

extension AppSession {
    /// Takes a tapped exercise off the new workout's card, which goes with its last; the screen
    /// adds the exercise as a pick adds it.
    public func useCardExercise(_ id: Exercise.ID) {
        newWorkoutCard = newWorkoutCard?.using(id)
    }

    /// Closes the new workout's card, for good on that workout.
    public func closeNewWorkoutCard() {
        newWorkoutCard = nil
    }
}
