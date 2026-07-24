import Foundation

/// The feature bag a similarity score reads — the three signals the model
/// carries that say "this move is like that one": the coarse muscle group,
/// the movement family it reads as, and the gear it needs. Pure value type,
/// so the ranker is Linux-testable with no `@Model` in sight (the app maps
/// its `Exercise` rows into this).
public struct ExerciseSimilarityFeatures: Sendable, Equatable {
    public var muscleGroup: MuscleGroup
    public var modality: ExerciseModality
    /// The exercise's required equipment, by name. Empty = bodyweight.
    public var equipmentNames: Set<String>

    public init(muscleGroup: MuscleGroup, modality: ExerciseModality, equipmentNames: Set<String>) {
        self.muscleGroup = muscleGroup
        self.modality = modality
        self.equipmentNames = equipmentNames
    }
}

/// How good a substitute one exercise is for another — the "Swap for…"
/// suggestions ranker (2026-07-24). Deliberately blunt: the model carries
/// exactly three comparable signals, so the score is a fixed weighted sum
/// of them, no learning, no history. Muscle group dominates (it is the only
/// muscle signal, and swapping a press for a curl is wrong), then the
/// movement family (don't offer a treadmill run for a bench press), then
/// gear overlap (the same equipment reads as the closest sub, but a
/// bodyweight alternative is still a fine swap, so it is the lightest
/// weight). All three normalize to 0…1, so `score` is 0…1.
public enum ExerciseSimilarity {
    /// Relative weights, summing to 1. Muscle is the spine of the score.
    static let muscleWeight = 0.6
    static let modalityWeight = 0.25
    static let equipmentWeight = 0.15

    /// A 0…1 substitutability score: 1 means an identical feature bag, 0
    /// means nothing in common. Symmetric in its inputs.
    public static func score(candidate: ExerciseSimilarityFeatures,
                             origin: ExerciseSimilarityFeatures) -> Double {
        let muscle = candidate.muscleGroup == origin.muscleGroup ? 1.0 : 0.0
        let modality = candidate.modality == origin.modality ? 1.0 : 0.0
        let equipment = jaccard(candidate.equipmentNames, origin.equipmentNames)
        return muscle * muscleWeight
            + modality * modalityWeight
            + equipment * equipmentWeight
    }

    /// Rank `items` best-first by their similarity to `origin`. A stable
    /// sort keys off the caller's incoming order for ties (the app hands
    /// these in name order), so equally-similar moves stay alphabetical.
    public static func ranked<T>(_ items: [T],
                                 like origin: ExerciseSimilarityFeatures,
                                 features: (T) -> ExerciseSimilarityFeatures) -> [T] {
        items
            .map { (item: $0, score: score(candidate: features($0), origin: origin)) }
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.score != rhs.element.score { return lhs.element.score > rhs.element.score }
                return lhs.offset < rhs.offset
            }
            .map(\.element.item)
    }

    /// Set overlap, |A ∩ B| / |A ∪ B|. Two bodyweight moves (both empty)
    /// count as a full match — sharing "no gear needed" is a real signal.
    private static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        if a.isEmpty && b.isEmpty { return 1.0 }
        let union = a.union(b)
        guard !union.isEmpty else { return 1.0 }
        return Double(a.intersection(b).count) / Double(union.count)
    }
}
