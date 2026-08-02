import Foundation

/// What a catalog and a kit add up to: how much of the catalog the kit can
/// actually do, and how that splits across the two axes people think in
/// (the muscle a move is FOR, and the movement family it files under).
///
/// This is the arithmetic behind the catalog's front matter (2026-08-02).
/// The list surfaces already GROUP by kit availability — the missing-
/// equipment disclosure — but nothing ever stated the totals, so the one
/// genuinely decision-useful fact the app holds stayed implicit. Pure value
/// math over `ExerciseSimilarityFeatures`, so it is Linux-tested and the
/// CLI can reach it; the app maps its `Exercise` rows into the bag it
/// already builds for the swap ranker.
///
/// ⚠️ Every count here is over the WHOLE catalog handed in. Nothing is
/// hidden by the kit (#113 flag-don't-hide) — `doable` and `total` are
/// stated side by side precisely so the frame is "what this opens", never
/// "what you lack".
public struct CatalogReach: Equatable, Sendable {

    /// One axis value and its two counts. `total` is every move filed
    /// under it; `doable` is the subset the kit can do today.
    public struct Bucket<Value: Hashable & Sendable>: Identifiable, Equatable, Sendable {
        public let value: Value
        public let total: Int
        public let doable: Int

        public var id: Value { value }

        public init(value: Value, total: Int, doable: Int) {
            self.value = value
            self.total = total
            self.doable = doable
        }
    }

    /// Every exercise handed in.
    public let total: Int
    /// Those whose whole equipment list is in the kit.
    public let doable: Int
    /// Those needing nothing at all. A subset of `doable`, and never a
    /// lesser answer: "bodyweight only" is a real kit (the anti-shame law).
    public let noEquipment: Int
    /// Buckets in `MuscleGroup.allCases` order, empty ones dropped.
    public let byMuscle: [Bucket<MuscleGroup>]
    /// Buckets in `MovementPattern.allCases` order, empty ones dropped.
    public let byPattern: [Bucket<MovementPattern>]

    public init(
        total: Int,
        doable: Int,
        noEquipment: Int,
        byMuscle: [Bucket<MuscleGroup>],
        byPattern: [Bucket<MovementPattern>]
    ) {
        self.total = total
        self.doable = doable
        self.noEquipment = noEquipment
        self.byMuscle = byMuscle
        self.byPattern = byPattern
    }
}

public enum CatalogReachCalculator {

    /// Whether a kit can do a move: it needs everything the move names.
    /// The pure mirror of the app's `ExerciseFilterState.missingEquipment(
    /// for:available:).isEmpty`, which stays the call site over live
    /// models — the two must agree, and a subset test is the whole rule.
    public static func canDo(_ features: ExerciseSimilarityFeatures, kit: Set<String>) -> Bool {
        features.equipmentNames.isSubset(of: kit)
    }

    /// One pass over the catalog, producing every count the front matter
    /// states.
    ///
    /// ⚠️ Muscle buckets file under the PRIMARY group only. An exercise
    /// works several and the list is primary-first by construction
    /// (`MuscleGroups.normalized`), so bucketing by every group would make
    /// the columns sum past the catalog size and read as a miscount. The
    /// facet a bucket writes still matches on ANY group, which is the
    /// honest asymmetry: the count says what this muscle is FOR, the
    /// filtered list then shows everything that touches it.
    ///
    /// ⚠️ A move with no movement pattern is ABSENT from `byPattern`, not
    /// bucketed as a null. Cardio carries none, most isolation carries
    /// none, and a custom carries none until its owner says otherwise
    /// (#495) — an "unclassified" bucket would be the catalog's largest
    /// and mean nothing.
    public static func reach(
        _ catalog: [ExerciseSimilarityFeatures],
        kit: Set<String>
    ) -> CatalogReach {
        var muscleTotals: [MuscleGroup: (total: Int, doable: Int)] = [:]
        var patternTotals: [MovementPattern: (total: Int, doable: Int)] = [:]
        var doable = 0
        var noEquipment = 0

        for features in catalog {
            let can = canDo(features, kit: kit)
            if can { doable += 1 }
            if features.equipmentNames.isEmpty { noEquipment += 1 }

            let muscle = features.muscleGroup
            var muscleEntry = muscleTotals[muscle] ?? (0, 0)
            muscleEntry.total += 1
            if can { muscleEntry.doable += 1 }
            muscleTotals[muscle] = muscleEntry

            if let pattern = features.movementPattern {
                var patternEntry = patternTotals[pattern] ?? (0, 0)
                patternEntry.total += 1
                if can { patternEntry.doable += 1 }
                patternTotals[pattern] = patternEntry
            }
        }

        return CatalogReach(
            total: catalog.count,
            doable: doable,
            noEquipment: noEquipment,
            byMuscle: buckets(MuscleGroup.allCases, muscleTotals),
            byPattern: buckets(MovementPattern.allCases, patternTotals)
        )
    }

    /// What ONE absent piece would open: for each piece the kit does not
    /// hold, how many exercises it alone stands between you and.
    ///
    /// This is the fact the app has always been able to state and never
    /// did — the kit knows exactly what it can do, and until now that only
    /// ever GROUPED results. Keyed by equipment name, the identity the kit
    /// matches on everywhere.
    ///
    /// ⚠️ The count is MARGINAL and truthful, never "everything that uses
    /// this". A piece that is one of TWO things a move is missing scores
    /// nothing for that move until the other arrives, so the numbers never
    /// overclaim — the same rule `EquipmentDetailScreen`'s "+N" unlock
    /// beat has always used, which is why that beat now reads from here
    /// rather than counting for itself. Pieces already in the kit are
    /// ABSENT from the map: they cannot open anything, and a zero would
    /// invite a caller to print one.
    ///
    /// ⚠️ Single pieces only. A bench and a barbell together are worth more
    /// than the sum of their entries, and nothing here says so — stating
    /// that would make this a solver rather than a fact.
    public static func unlocks(
        _ catalog: [ExerciseSimilarityFeatures],
        kit: Set<String>
    ) -> [String: Int] {
        var counts: [String: Int] = [:]
        for features in catalog {
            let missing = features.equipmentNames.subtracting(kit)
            // Exactly one thing in the way: that piece is what opens it.
            guard missing.count == 1, let only = missing.first else { continue }
            counts[only, default: 0] += 1
        }
        return counts
    }

    /// Buckets in the enum's own declaration order — a stable, authored
    /// order beats sorting by count, which would reshuffle the row every
    /// time the kit changed.
    private static func buckets<Value: Hashable & Sendable>(
        _ order: [Value],
        _ counts: [Value: (total: Int, doable: Int)]
    ) -> [CatalogReach.Bucket<Value>] {
        order.compactMap { value in
            guard let entry = counts[value], entry.total > 0 else { return nil }
            return CatalogReach.Bucket(value: value, total: entry.total, doable: entry.doable)
        }
    }
}
