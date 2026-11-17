extension Exercise {
    /// The rest after each set for a set of `target`, in seconds: none for a stretch; a timed
    /// set's own time, up to the longest rest; else by planned reps (5 or fewer, 6–12, 13 or more)
    /// and kind:
    ///
    /// | Reps  | Lower-body compound | Upper-body compound | Single-joint |
    /// | ≤ 5   | 3 min               | 2 min 30 s          | 2 min        |
    /// | 6–12  | 2 min               | 90 s                | 60 s         |
    /// | ≥ 13  | 90 s                | 60 s                | 45 s         |
    ///
    /// With no load (bodyweight or a band) one step shorter: one row down, and from the last row
    /// the next kind's, never under 45 s; not for bodyweight near most people's max (a pull-up).
    func defaultRest(for target: SetTarget) -> Int {
        if tags.kind == .stretch {
            return 0
        }
        switch target {
        case let .time(seconds):
            // Held to what a rest can be stored and stepped as.
            return min(seconds, PlanLimits.rest.upperBound)
        case let .reps(reps):
            let row = reps <= 5 ? 0 : reps <= 12 ? 1 : 2
            let column = restKind.rawValue
            guard load == nil, !tags.nearMax else { return Self.restTable[row][column] }
            return row < 2 ? Self.restTable[row + 1][column]
                : Self.restTable[2][min(column + 1, RestKind.singleJoint.rawValue)]
        }
    }

    private static let restTable = [
        [180, 150, 120],
        [120, 90, 60],
        [90, 60, 45],
    ]
}

/// How an exercise rests, the column of `defaultRest(for:)`'s table.
enum RestKind: Int, Sendable {
    case lowerCompound
    case upperCompound
    case singleJoint

    /// Squat, hinge, and lunge patterns are lower-body compounds; push and pull, upper; anything
    /// else (a single-joint lift, a hold, a rotation, no pattern at all) rests as single-joint.
    init(tags: ExerciseTags) {
        guard !tags.singleJoint else {
            self = .singleJoint
            return
        }
        switch tags.movement {
        case .squat, .hinge, .lunge: self = .lowerCompound
        case .push, .pull: self = .upperCompound
        default: self = .singleJoint
        }
    }

    /// For an exercise known only by its groups, the longest-resting of them: any legs as a
    /// lower-body compound; else any of chest, back, and shoulders as an upper-body one; else
    /// (arms, core) single-joint.
    init(groups: Set<MuscleGroup>) {
        if groups.contains(.legs) {
            self = .lowerCompound
        } else if !groups.isDisjoint(with: [.chest, .back, .shoulders]) {
            self = .upperCompound
        } else {
            self = .singleJoint
        }
    }
}

extension RoutineExercise {
    /// The rest after each set: the exercise's for these reps or time while automatic, else the
    /// one the user set.
    public var rest: Int {
        plan.rest.seconds(derived: autoRest)
    }

    private var autoRest: Int {
        exercise.defaultRest(for: plan.target)
    }

    /// Whether the rest is automatic, following the reps or time. Turning it on keeps the rest
    /// set by hand for later; turning it off brings that back, or, if there is none, keeps the
    /// rest it reads now.
    public var isRestAuto: Bool {
        get { plan.rest.isAuto }
        set { plan.rest = plan.rest.settingAuto(newValue, derived: autoRest) }
    }
}
