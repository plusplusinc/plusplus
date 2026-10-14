/// Whether an upper-body exercise pushes or pulls, so a routine of them is named a push or a
/// pull day. The on-device model couldn't tell them apart reliably from the names alone.
enum Movement {
    case push
    case pull
}

extension Exercise {
    /// Nil for anything that is neither, legs, core, and stretches.
    var movement: Movement? {
        if Self.pushes.contains(id) {
            return .push
        }
        if Self.pulls.contains(id) {
            return .pull
        }
        return nil
    }

    private static let pushes: Set<String> = [
        "push-up", "ring-push-up", "dumbbell-bench-press", "incline-dumbbell-press",
        "barbell-bench-press", "ring-dip", "overhead-press", "barbell-overhead-press",
        "lateral-raise", "triceps-extension",
    ]
    private static let pulls: Set<String> = [
        "pull-up", "chin-up", "inverted-row", "dumbbell-row", "barbell-row", "dead-hang",
        "face-pull", "band-pull-apart", "biceps-curl", "hammer-curl",
    ]
}
