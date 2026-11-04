extension Exercise {
    /// The rest after each set for a set of `target`, in seconds: none for a stretch; a timed
    /// set's own time; else by planned reps (5 or fewer, 6–12, 13 or more) and kind:
    ///
    /// | Reps  | Lower-body compound | Upper-body compound | Single-joint |
    /// | ≤ 5   | 3 min               | 2 min 30 s          | 2 min        |
    /// | 6–12  | 2 min               | 90 s                | 60 s         |
    /// | ≥ 13  | 90 s                | 60 s                | 45 s         |
    ///
    /// With no load (bodyweight or a band) one step shorter: one row down, and from the last row
    /// the next kind's, never under 45 s.
    func defaultRest(for target: SetTarget) -> Int {
        if tags.kind == .stretch {
            return 0
        }
        switch target {
        case let .time(seconds):
            return seconds
        case let .reps(reps):
            let row = reps <= 5 ? 0 : reps <= 12 ? 1 : 2
            let column = restKind.rawValue
            guard load == nil else { return Self.restTable[row][column] }
            return row < 2 ? Self.restTable[row + 1][column]
                : Self.restTable[2][min(column + 1, RestKind.singleJoint.rawValue)]
        }
    }

    private static let restTable = [
        [180, 150, 120],
        [120, 90, 60],
        [90, 60, 45],
    ]

    /// Squat, hinge, and lunge patterns are lower-body compounds; push and pull, upper; anything
    /// else (a single-joint lift, a hold, a rotation, no pattern at all) rests as single-joint.
    private var restKind: RestKind {
        guard !tags.singleJoint else { return .singleJoint }
        switch tags.movement {
        case .squat, .hinge, .lunge: return .lowerCompound
        case .push, .pull: return .upperCompound
        default: return .singleJoint
        }
    }

    private enum RestKind: Int {
        case lowerCompound
        case upperCompound
        case singleJoint
    }
}

extension RoutineExercise {
    /// The rest after each set: the one the user set, else the exercise's for these reps or time.
    public var rest: Int {
        plan.rest ?? exercise.defaultRest(for: plan.target)
    }
}
