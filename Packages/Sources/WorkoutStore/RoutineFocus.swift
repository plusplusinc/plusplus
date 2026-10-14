/// What a routine mostly works, worked out from its exercises' tags, so its name is honest
/// about it.
enum RoutineFocus: Equatable {
    /// Mostly stretches, over one part of the body or several.
    case mobility(StretchRegion)
    /// One group does most of the work.
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
    case fullBody

    enum StretchRegion: CaseIterable {
        case lowerBody
        case upperBody
        case back
        case wholeBody
    }

    private static let upper: Set<MuscleGroup> = [.chest, .back, .shoulders, .arms]

    /// Stretches as a clear majority (seven in ten) is mobility. Otherwise the rest, the work,
    /// is named for the group that does three in five of it; else its two groups, unless both
    /// are upper body; else the parts of the body it spans, which is then the upper body at
    /// least, since legs and core on their own are a pair. Upper body alone is a push or a pull
    /// when two in three of it is, so push-ups and an overhead press are a push day.
    init(of exercises: [Exercise]) {
        let work = exercises.filter { !$0.isStretch }
        guard !work.isEmpty, (exercises.count - work.count) * 10 < exercises.count * 7 else {
            self = .mobility(Self.region(of: exercises.filter(\.isStretch)))
            return
        }
        let counts = Dictionary(grouping: work, by: \.muscleGroup).mapValues(\.count)
        let groups = MuscleGroup.allCases.filter { counts[$0] != nil }
        if let main = groups.first(where: { (counts[$0] ?? 0) * 5 >= work.count * 3 }) {
            self = .group(main)
        } else if groups.count == 2, !Self.upper.isSuperset(of: groups) {
            self = .pair(groups[0], groups[1])
        } else if counts[.legs] != nil {
            self = .fullBody
        } else if counts[.core] != nil {
            self = .upperBodyAndCore
        } else {
            self = Self.upperBody(work)
        }
    }

    private static func upperBody(_ exercises: [Exercise]) -> Self {
        let pushes = exercises.count { $0.tags.movement == .push }
        let pulls = exercises.count { $0.tags.movement == .pull }
        if pushes * 3 >= (pushes + pulls) * 2 {
            return .push
        }
        if pulls * 3 >= (pushes + pulls) * 2 {
            return .pull
        }
        return .upperBody
    }

    /// The part of the body two in three of the stretches are for, else the whole body.
    private static func region(of stretches: [Exercise]) -> StretchRegion {
        let regions = stretches.map(\.stretchRegion)
        return StretchRegion.allCases.first { region in
            regions.count { $0 == region } * 3 >= regions.count * 2
        } ?? .wholeBody
    }

    /// The name, kept honest: a bare group becomes its day ("Core" is "Core day"), and a name
    /// that mentions a group or muscle the routine doesn't work gives way to the muscle-group
    /// name, or its day for one group. A stretch counts only in a mobility routine: a chest
    /// stretch after back and legs work doesn't make it a chest routine.
    func checked(_ name: String, against exercises: [Exercise]) -> String {
        let words = Set(name.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        let worked = if case .mobility = self {
            exercises
        } else {
            exercises.filter { !$0.isStretch }
        }
        let groups = Set(worked.map(\.muscleGroup))
        let muscles = Set(worked.flatMap(\.tags.primary))
        let mentioned = MuscleGroup.allCases.filter { !words.isDisjoint(with: $0.words) }
        let honest = mentioned.allSatisfy(groups.contains)
            && ExerciseTags.Muscle.words.allSatisfy { word, claimed in
                !words.contains(word) || !muscles.isDisjoint(with: claimed)
            }
        guard honest else {
            let present = Set(exercises.map(\.muscleGroup))
            if present.count == 1, let only = present.first {
                return only.dayName
            }
            return MuscleGroup.routineName(for: present) ?? name
        }
        if words.count == 1, let group = mentioned.first {
            return group.dayName
        }
        return name
    }
}

extension Exercise {
    /// Where a stretch is felt, from the muscles it works first.
    fileprivate var stretchRegion: RoutineFocus.StretchRegion {
        let regions = tags.primary.map(\.region)
        return RoutineFocus.StretchRegion.allCases.max { first, second in
            regions.count { $0 == first } < regions.count { $0 == second }
        } ?? .wholeBody
    }
}

extension ExerciseTags.Muscle {
    fileprivate var region: RoutineFocus.StretchRegion {
        switch self {
        case .chest, .frontDelts, .sideDelts, .rearDelts, .biceps, .triceps, .forearms: .upperBody
        case .lats, .upperBack, .lowerBack, .abs, .obliques: .back
        case .hipFlexors, .glutes, .quads, .hamstrings, .calves: .lowerBody
        }
    }

    /// The finer words a name may use, and the muscles that make each one honest.
    fileprivate static let words: [String: Set<Self>] = [
        "biceps": [.biceps],
        "triceps": [.triceps],
        "grip": [.forearms],
        "forearms": [.forearms],
        "glutes": [.glutes],
        "hamstrings": [.hamstrings],
        "hips": [.glutes, .hipFlexors, .hamstrings],
        "hip": [.glutes, .hipFlexors, .hamstrings],
        "calves": [.calves],
        "obliques": [.obliques],
    ]
}

extension MuscleGroup {
    /// The words a name uses for the group.
    fileprivate var words: Set<String> {
        switch self {
        case .chest: ["chest"]
        case .back: ["back"]
        case .shoulders: ["shoulder", "shoulders"]
        case .arms: ["arm", "arms"]
        case .legs: ["leg", "legs"]
        case .core: ["core", "abs"]
        }
    }

    /// "Leg day", "Core day".
    var dayName: String {
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
