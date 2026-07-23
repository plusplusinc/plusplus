import Foundation

/// The mascot's animation catalog, keyed by built-in exercise name —
/// the same name-keyed curated-data pattern as the app's
/// `builtInProfilesByName` (exercise identity IS the name, so no model
/// column, no migration, no interchange field). An exercise without an
/// entry simply has no form demo; custom exercises never match.
public enum MascotMoves {
    public static let all: [ExerciseAnimation] = [
        SquatMove.animation,
        DeadliftMove.animation,
        BenchPressMove.animation,
        PushUpMove.animation,
        DumbbellCurlMove.animation,
        PlankMove.animation,
        SingleLegCalfRaiseMove.animation,
        LateralRaiseMove.animation,
        GluteBridgeMove.animation,
        SitUpMove.animation,
        OverheadPressMove.animation,
        BarbellRowMove.animation,
        GobletSquatMove.animation,
        PullUpMove.animation,
        JumpSquatMove.animation,
        KettlebellSwingMove.animation,
        ReverseLungeMove.animation,
    ]

    private static let animationsByName: [String: ExerciseAnimation] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.exerciseName, $0) })

    public static func animation(forExerciseNamed name: String) -> ExerciseAnimation? {
        animationsByName[name]
    }
}
