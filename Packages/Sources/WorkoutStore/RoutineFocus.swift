/// What a routine mostly works, worked out from its exercises, so a generated name is honest
/// about it.
enum RoutineFocus: Equatable {
    /// Mostly stretches.
    case mobility
    /// One group does most of the strength work.
    case group(MuscleGroup)
    /// Two groups share it, in declaration order.
    case pair(MuscleGroup, MuscleGroup)
    /// Upper body, two in three of it pushing.
    case push
    /// Upper body, two in three of it pulling.
    case pull
    /// Upper body, pushing and pulling about evenly.
    case upperBody
    case upperBodyAndCore
    case legsAndCore
    case fullBody

    private static let upper: Set<MuscleGroup> = [.chest, .back, .shoulders, .arms]

    /// Stretches as a clear majority (seven in ten) is mobility. Otherwise the strength work is
    /// named for the group that does three in five of it; else its two groups, unless both are
    /// upper body; else the parts of the body it spans. Upper body alone is a push or a pull when
    /// two in three of it is, so push-ups and an overhead press are a push day.
    init(of exercises: [Exercise]) {
        let strength = exercises.filter { !$0.isStretch }
        guard !strength.isEmpty, (exercises.count - strength.count) * 10 < exercises.count * 7
        else {
            self = .mobility
            return
        }
        let counts = Dictionary(grouping: strength, by: \.muscleGroup).mapValues(\.count)
        let groups = MuscleGroup.allCases.filter { counts[$0] != nil }
        if let main = groups.first(where: { (counts[$0] ?? 0) * 5 >= strength.count * 3 }) {
            self = .group(main)
        } else if groups.count == 2, !Self.upper.isSuperset(of: groups) {
            self = .pair(groups[0], groups[1])
        } else {
            let hasUpper = !Self.upper.isDisjoint(with: groups)
            self = switch (hasUpper, counts[.legs] != nil, counts[.core] != nil) {
            case (true, true, _): .fullBody
            case (true, false, true): .upperBodyAndCore
            case (true, false, false): Self.upperBody(strength)
            default: .legsAndCore
            }
        }
    }

    private static func upperBody(_ exercises: [Exercise]) -> Self {
        let pushes = exercises.count { $0.movement == .push }
        let pulls = exercises.count { $0.movement == .pull }
        if pushes * 3 >= (pushes + pulls) * 2 {
            return .push
        }
        if pulls * 3 >= (pushes + pulls) * 2 {
            return .pull
        }
        return .upperBody
    }

    /// The focus in the words the model is given.
    var phrase: String {
        switch self {
        case .mobility: "mobility and stretching"
        case let .group(group): group.name.lowercased()
        case let .pair(first, second): "\(first.name.lowercased()) and \(second.name.lowercased())"
        case .push: "push"
        case .pull: "pull"
        case .upperBody: "upper body"
        case .upperBodyAndCore: "upper body and core"
        case .legsAndCore: "legs and core"
        case .fullBody: "full body"
        }
    }

    /// A plain name for the focus, for when the model's answer won't do.
    var name: String {
        switch self {
        case .mobility: "Stretch and reset"
        case let .group(group): group.dayName
        case let .pair(first, second): "\(first.name) and \(second.name.lowercased())"
        case .push: "Push day"
        case .pull: "Pull day"
        case .upperBody: "Upper body"
        case .upperBodyAndCore: "Upper body and core"
        case .legsAndCore: "Legs and core"
        case .fullBody: "Full body"
        }
    }

    /// The model's answer, kept honest: a bare group becomes its day ("Core" is "Core day"),
    /// and a name that mentions a group the routine doesn't strengthen gives way to the focus's
    /// own. A stretch counts only in a mobility routine: a chest stretch after back and legs work
    /// doesn't make it a chest routine.
    func checked(_ name: String, against exercises: [Exercise]) -> String {
        let words = Set(name.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        let mentioned = MuscleGroup.allCases.filter { !words.isDisjoint(with: $0.words) }
        let worked = self == .mobility ? exercises : exercises.filter { !$0.isStretch }
        let present = Set(worked.map(\.muscleGroup))
        if mentioned.contains(where: { !present.contains($0) }) {
            return self.name
        }
        if words.count == 1, let group = mentioned.first {
            return group.dayName
        }
        return name
    }
}

extension MuscleGroup {
    /// The words a name uses for the group.
    fileprivate var words: Set<String> {
        switch self {
        case .chest: ["chest"]
        case .back: ["back"]
        case .shoulders: ["shoulder", "shoulders"]
        case .arms: ["arm", "arms", "biceps", "triceps"]
        case .legs: ["leg", "legs", "glute", "glutes"]
        case .core: ["core", "abs"]
        }
    }

    /// "Leg day", "Core day".
    fileprivate var dayName: String {
        switch self {
        case .chest: "Chest day"
        case .back: "Back day"
        case .shoulders: "Shoulder day"
        case .arms: "Arm day"
        case .legs: "Leg day"
        case .core: "Core day"
        }
    }
}
