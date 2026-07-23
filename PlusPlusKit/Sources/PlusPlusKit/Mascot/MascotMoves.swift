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
        // PullUpMove is temporarily OUT of the catalog: the build-117
        // articulation round re-authored its grip and elbows (the hang
        // and top configs pass every law), but the PATH between them
        // needs a better-conditioned station pin than this round could
        // land — the roll-bisection whips between solutions mid-pull.
        // No demo beats a broken one; the re-author is the follow-up.
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
