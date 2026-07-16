import Foundation

/// The Operator safety tiers (Dave, 2026-07-15): small reversible edits
/// apply immediately with an inline undo; bulk or destructive changes
/// stage a preview card and touch nothing until the user taps Apply.
public enum ChangeTier: String, Equatable, Sendable {
    case applyNow
    case previewRequired
}

/// Pure tiering policy — the app's change engine feeds it the RESOLVED
/// facts (how many things, whether tracking converts, whether routine
/// entries are dragged along) and renders the verdict. Table-tested.
public enum ChangeTierPolicy {
    /// More affected items than this always previews.
    public static let bulkThreshold = 3

    /// - Parameters:
    ///   - affectedCount: resolved entities the spec will touch.
    ///   - changesTracking: the change converts how an exercise is
    ///     tracked (`values.trackBy`) — target-shape churn, so it only
    ///     auto-applies for a single exercise with no live entries.
    ///   - cascadesToEntries: live `RoutineExercise` rows are rewritten
    ///     as a consequence (the tracking cascade).
    ///   - replacesMembership: `values.equipment` on a library update —
    ///     the whole member list is restated, so everything omitted is
    ///     removed.
    public static func tier(
        operation: ChangeOperation,
        entity: ChangeEntity,
        affectedCount: Int,
        changesTracking: Bool = false,
        cascadesToEntries: Bool = false,
        replacesMembership: Bool = false
    ) -> ChangeTier {
        // Destructive: deleting a persistent entity always previews, no
        // matter how small. (A superset "delete" only dissolves grouping —
        // structural, reversible, so it rides the count rules instead.)
        if operation == .delete, entity != .superset {
            return .previewRequired
        }
        // Replacing a library's member list is a delete in disguise:
        // whatever the spec forgot to restate silently leaves. Deltas
        // (addEquipment/removeEquipment) ride the count rules instead.
        if operation == .update, replacesMembership {
            return .previewRequired
        }
        if changesTracking, affectedCount > 1 || cascadesToEntries {
            return .previewRequired
        }
        if affectedCount > bulkThreshold {
            return .previewRequired
        }
        return .applyNow
    }
}

/// The preview card's text, computed from resolved facts. Pure
/// formatting — copy laws apply (sentence case, no em dashes, "·"
/// separators, no obligation words).
public struct ChangePreviewSummary: Equatable, Sendable {
    /// "Changes 14 exercises" / "Deletes 1 routine".
    public var headline: String
    /// Field deltas first ("track by duration · was reps"), then the
    /// sample-names line ("Standing Hamstring Stretch, Butterfly
    /// Stretch, +12 more").
    public var lines: [String]

    public init(headline: String, lines: [String]) {
        self.headline = headline
        self.lines = lines
    }

    public static func make(
        operation: ChangeOperation,
        entity: ChangeEntity,
        count: Int,
        sampleNames: [String],
        changeDescriptions: [String]
    ) -> ChangePreviewSummary {
        let verb: String
        switch operation {
        case .create: verb = "Creates"
        case .update: verb = "Changes"
        case .delete: verb = "Deletes"
        }
        var lines = changeDescriptions.filter { !$0.isEmpty }
        if let samples = samplesLine(names: sampleNames, total: count) {
            lines.append(samples)
        }
        return ChangePreviewSummary(
            headline: "\(verb) \(entity.countNoun(count))",
            lines: lines
        )
    }

    /// Up to three names, then "+N more". nil when there are no names.
    public static func samplesLine(names: [String], total: Int, showing: Int = 3) -> String? {
        let shown = names.prefix(showing)
        guard !shown.isEmpty else { return nil }
        let remainder = total - shown.count
        let base = shown.joined(separator: ", ")
        return remainder > 0 ? "\(base), +\(remainder) more" : base
    }
}
