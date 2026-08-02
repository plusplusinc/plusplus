import Foundation

/// The feature bag a similarity score reads — the three signals the model
/// carries that say "this move is like that one": the muscle groups it
/// works, the movement family it reads as, and the gear it needs. Pure
/// value type, so the ranker is Linux-testable with no `@Model` in sight
/// (the app maps its `Exercise` rows into this).
public struct ExerciseSimilarityFeatures: Sendable, Equatable {
    /// Every group the move works, PRIMARY FIRST — order is meaning here,
    /// not presentation (see `muscleScore`). Never empty.
    public var muscleGroups: [MuscleGroup]
    public var modality: ExerciseModality
    /// The exercise's required equipment, by name. Empty = bodyweight.
    public var equipmentNames: Set<String>
    /// The authored program bucket, when the exercise has one (#495).
    /// nil is the common, honest case — cardio carries none, most
    /// isolation carries none, and a custom carries none until its
    /// owner says otherwise — so the score treats it as UNAVAILABLE
    /// rather than as a mismatch (see `score`).
    public var movementPattern: MovementPattern?
    /// Compound vs isolation. Present on nearly every strength row, and
    /// the signal that separates the case #495 was filed for: a
    /// Romanian Deadlift and a Leg Curl share hamstrings and gear-lessness
    /// but are not substitutes, and only this tells them apart (the
    /// curl carries no pattern to compare).
    public var mechanic: ExerciseMechanic?

    /// The group the move is FOR. A feature bag is always built from a real
    /// exercise, which always has one; the fallback keeps this total rather
    /// than making every reader unwrap.
    public var muscleGroup: MuscleGroup { muscleGroups.first ?? .fullBody }

    public init(
        muscleGroups: [MuscleGroup],
        modality: ExerciseModality,
        equipmentNames: Set<String>,
        movementPattern: MovementPattern? = nil,
        mechanic: ExerciseMechanic? = nil
    ) {
        self.muscleGroups = muscleGroups.isEmpty ? [.fullBody] : muscleGroups
        self.modality = modality
        self.equipmentNames = equipmentNames
        self.movementPattern = movementPattern
        self.mechanic = mechanic
    }

    public init(
        muscleGroup: MuscleGroup,
        modality: ExerciseModality,
        equipmentNames: Set<String>,
        movementPattern: MovementPattern? = nil,
        mechanic: ExerciseMechanic? = nil
    ) {
        self.init(
            muscleGroups: [muscleGroup],
            modality: modality,
            equipmentNames: equipmentNames,
            movementPattern: movementPattern,
            mechanic: mechanic
        )
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
    /// Relative weights. Muscle stays the spine; the two authored
    /// attributes (#495) sit between it and the gear term, since "same
    /// bucket of movement" is a stronger substitution signal than "same
    /// gear" and a weaker one than "same muscle".
    ///
    /// ⚠️ They sum to 1 only when EVERY signal is comparable. When an
    /// attribute is absent on either side the score renormalizes over
    /// what is left (see `score`), so these are ratios, not a fixed
    /// budget — which is what keeps a nil-attribute pair scoring exactly
    /// as it did before the attributes existed.
    static let muscleWeight = 0.45
    static let patternWeight = 0.20
    static let modalityWeight = 0.15
    static let mechanicWeight = 0.10
    static let equipmentWeight = 0.10
    /// How much of the muscle score the PRIMARY group carries, the rest
    /// going to overlap across the full lists.
    static let primaryShare = 0.7

    /// Family closeness, 0…1.
    ///
    /// ⚠️ Partial credit matters now that `.cardio` has split into named
    /// families. A straight equality test scored Treadmill Run against
    /// Elliptical at ZERO — the same as against a burpee — because they
    /// used to share one `.cardio` case and no longer do. An elliptical
    /// is still a far better substitute for a treadmill than a barbell
    /// is, and this is a substitution ranker.
    static func modalityScore(_ candidate: ExerciseModality, _ origin: ExerciseModality) -> Double {
        if candidate == origin { return 1.0 }
        return candidate.isCardio == origin.isCardio ? 0.5 : 0.0
    }

    /// A 0…1 substitutability score: 1 means an identical feature bag, 0
    /// means nothing in common. Symmetric in its inputs.
    ///
    /// ⚠️ An ABSENT attribute is unavailable, not a mismatch (#495). A
    /// pattern or mechanic that either side doesn't carry drops out of
    /// the sum and its weight is redistributed across the rest — scoring
    /// it zero would push every cardio row, every stretch and every
    /// custom down the list for saying nothing, and scoring it one would
    /// hand them free credit. Renormalizing keeps a pair with no
    /// attributes scoring exactly what it scored before they existed,
    /// which is why the pre-attribute ranking tests still hold.
    public static func score(candidate: ExerciseSimilarityFeatures,
                             origin: ExerciseSimilarityFeatures) -> Double {
        var weighted = muscleScore(candidate.muscleGroups, origin.muscleGroups) * muscleWeight
            + modalityScore(candidate.modality, origin.modality) * modalityWeight
            + jaccard(candidate.equipmentNames, origin.equipmentNames) * equipmentWeight
        var total = muscleWeight + modalityWeight + equipmentWeight

        if let a = candidate.movementPattern, let b = origin.movementPattern {
            weighted += (a == b ? 1.0 : 0.0) * patternWeight
            total += patternWeight
        }
        if let a = candidate.mechanic, let b = origin.mechanic {
            weighted += (a == b ? 1.0 : 0.0) * mechanicWeight
            total += mechanicWeight
        }
        return weighted / total
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

    /// Muscle agreement, PRIMARY-WEIGHTED: matching what the two moves are
    /// FOR carries most of it, and shared secondaries top it up.
    ///
    /// A flat Jaccard would be wrong in a way that shows: a Dumbbell Fly
    /// (chest) against a Bench Press (chest · triceps · shoulders) scores
    /// 1/3, below a Skull Crusher (triceps · chest) at 2/3 — so the best
    /// chest swap in the catalog would rank under a triceps move. Breadth
    /// is not distance. Leading with the primary keeps "another chest
    /// move" ahead of "another move that happens to involve chest", and
    /// the overlap term still separates a near-twin from a bare match.
    static func muscleScore(_ a: [MuscleGroup], _ b: [MuscleGroup]) -> Double {
        let primary = a.first == b.first ? 1.0 : 0.0
        return primaryShare * primary + (1 - primaryShare) * jaccard(Set(a.map(\.rawValue)), Set(b.map(\.rawValue)))
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
