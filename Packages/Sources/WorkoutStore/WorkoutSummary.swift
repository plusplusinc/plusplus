/// A workout's shape, as its row on the Workouts list shows it and the list's filters read it:
/// how long it takes, which groups it mainly works and in what share, the kind most of its
/// exercises are, and the equipment it uses.
public struct WorkoutSummary: Equatable, Sendable {
    /// The estimated length, in seconds (`Workout.estimatedSeconds`).
    public let seconds: Int
    /// Every group the workout mainly works with its share of the sets, most first, a tie in
    /// body order. The shares sum to 1.
    public let muscles: [Muscle]
    public let kind: ExerciseKind
    /// In display order, once each; none for a workout of bodyweight exercises alone.
    public let equipment: [Equipment]

    public struct Muscle: Equatable, Sendable {
        public let group: MuscleGroup
        public let share: Double
    }

    /// Every muscle beyond those a row names, as one: how many and their share together.
    public struct Rest: Equatable, Sendable {
        public let count: Int
        public let share: Double
    }

    /// The seconds a rep takes: about a second and a half each way, so 10 reps is 30 s.
    public static let secondsPerRep = 3
    /// The shortest workout that fills a row's bar, in shown minutes.
    public static let shortestFullBar = 30

    /// The length as the row reads it and the Length filter compares: the estimate to the
    /// nearest 5 minutes, never under 5.
    public var minutes: Int {
        let fives = (Double(seconds) / 300).rounded()
        return max(5, Int(fives) * 5)
    }

    /// The first `limit` muscles, and the rest as one, nil when there is none.
    public func segments(limit: Int) -> (named: [Muscle], rest: Rest?) {
        guard muscles.count > limit else { return (muscles, nil) }
        let rest = muscles.dropFirst(limit)
        return (
            Array(muscles.prefix(limit)),
            Rest(count: rest.count, share: rest.map(\.share).reduce(0, +)),
        )
    }

    /// The minutes a full bar stands for among `summaries`, the workouts a list shows: the
    /// longest of them as their rows read (`minutes`), but never under `shortestFullBar`, so a
    /// list of short workouts draws no bar full, and an empty one never divides by zero. Shown
    /// minutes, so two rows that read the same length draw the same bar (decided 2026-11-22).
    public static func fullBarMinutes(among summaries: some Sequence<Self>) -> Int {
        max(shortestFullBar, summaries.map(\.minutes).max() ?? 0)
    }

    /// How much of a full bar of `fullBar` minutes this workout's bar fills.
    public func fill(of fullBar: Int) -> Double {
        min(1, Double(minutes) / Double(fullBar))
    }
}

extension Workout {
    /// How long the workout takes, in seconds, walked in the order its sets are done
    /// (`setOrder`): each set's work, and between each two the rest the live workout runs
    /// (`rest(after:before:)`), nothing after the last. A rep takes `secondsPerRep`; a timed set
    /// its seconds and the count-in before it (`LiveWorkout.startsIn`).
    public var estimatedSeconds: Int {
        let order = setOrder
        let rows = Dictionary(exercises.map { ($0.id, $0) }) { first, _ in first }
        var total = 0
        for (index, set) in order.enumerated() {
            if let row = rows[set.row] {
                switch row.plan.target {
                case let .reps(reps): total += reps * WorkoutSummary.secondsPerRep
                case let .time(seconds): total += seconds + LiveWorkout.startsIn
                }
            }
            let next = order.indices.contains(index + 1) ? order[index + 1] : nil
            total += rest(after: set, before: next)
        }
        return total
    }

    /// The workout's shape, nil with no exercises. A group's share counts each exercise's sets
    /// in full toward every group it mainly works (`Exercise.mainGroups`). The kind is the one
    /// most exercises are, a tie going Strength, Conditioning, Stretching.
    public var summary: WorkoutSummary? {
        guard !exercises.isEmpty else { return nil }
        var sets: [MuscleGroup: Int] = [:]
        var kinds: [ExerciseKind: Int] = [:]
        for row in exercises {
            for group in row.exercise.mainGroups {
                sets[group, default: 0] += max(row.plan.sets, 1)
            }
            kinds[row.exercise.kind, default: 0] += 1
        }
        let total = Double(sets.values.reduce(0, +))
        let muscles = MuscleGroup.allCases
            .filter { sets[$0] != nil }
            .enumerated()
            .sorted { (sets[$0.element] ?? 0, -$0.offset) > (sets[$1.element] ?? 0, -$1.offset) }
            .map { WorkoutSummary.Muscle(
                group: $0.element,
                share: Double(sets[$0.element] ?? 0) / total,
            ) }
        let kindOrder: [ExerciseKind] = [.strength, .conditioning, .stretch]
        let kind = kindOrder.enumerated()
            .max { (kinds[$0.element] ?? 0, -$0.offset) < (kinds[$1.element] ?? 0, -$1.offset) }?
            .element ?? .strength
        return WorkoutSummary(
            seconds: estimatedSeconds,
            muscles: muscles,
            kind: kind,
            equipment: exercises.map(\.exercise).equipment,
        )
    }
}
