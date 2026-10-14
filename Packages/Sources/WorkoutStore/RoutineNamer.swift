import Foundation
import OSLog

/// Names a routine from its exercises: for what they work, from their tags, in the routine's own
/// style. Written in code: Apple's on-device model, given the same tags, named routines less
/// sharply and less honestly.
public struct RoutineNamer: Sendable {
    private let usesTags: Bool

    private static let logger = Logger(subsystem: "com.plusplusinc.plusplus", category: "naming")
    /// Longer than this, a name doesn't fit one line of the title.
    static let longestName = 20

    /// Names for what the exercises work, from their tags.
    public static let standard = Self(usesTags: true)

    /// Muscle-group names only: "Legs", "Chest and back", "Full body".
    public static let muscleGroupsOnly = Self(usesTags: false)

    /// A name for these exercises, or nil for none. `routine` sets the name's style, so each
    /// routine keeps its own as its exercises change, and different routines differ.
    public func name(for exercises: [Exercise], of routine: Routine.ID) -> String? {
        let unique = Self.unique(exercises)
        guard let fallback = MuscleGroup.routineName(for: unique.map(\.muscleGroup)) else {
            return nil
        }
        guard usesTags else { return fallback }
        let focus = RoutineFocus(of: unique)
        let style = NameStyle(of: routine)
        guard let picked = style.pick(focus.names(for: unique)) else {
            Self.logger.notice("Named \(fallback, privacy: .public) from muscle groups: no name")
            return fallback
        }
        let name = focus.checked(picked, against: unique)
        let ids = unique.map(\.id).joined(separator: ", ")
        let named = "\(name) (\(style.hasCharacter ? "character" : "plain"))"
        Self.logger.notice("Named \(named, privacy: .public) for \(ids, privacy: .public)")
        if name != picked {
            Self.logger.notice(
                "Kept honest: \(picked, privacy: .public) became \(name, privacy: .public)",
            )
        }
        return name
    }

    private static func unique(_ exercises: [Exercise]) -> [Exercise] {
        var seen = Set<Exercise.ID>()
        return exercises.filter { seen.insert($0.id).inserted }
    }
}
