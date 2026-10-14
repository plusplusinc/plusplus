import Foundation

/// How a routine's generated name is worded, fixed by the routine's id: the same routine keeps
/// its style as its exercises change, and different routines differ.
struct NameStyle: Equatable {
    /// About one routine in three gets a lightly positive name; the rest stay plain.
    let isWarm: Bool
    /// Which of a focus's names the routine takes.
    let variant: Int

    init(of routine: UUID) {
        // From the id's own bytes, not `hashValue`, which changes from launch to launch.
        let bytes = withUnsafeBytes(of: routine.uuid) { Array($0.prefix(8)) }
        let seed = bytes.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        isWarm = seed.isMultiple(of: 3)
        variant = Int(seed / 3 % 6)
    }

    /// The routine's pick of the names: warm ones when it is warm and there are any.
    func pick(_ names: RoutineFocus.Names) -> String? {
        let options = isWarm && !names.warm.isEmpty ? names.warm : names.plain
        return options.isEmpty ? nil : options[variant % options.count]
    }
}

extension RoutineFocus {
    /// A focus's names in each tone, which a routine's style picks from.
    typealias Names = (plain: [String], warm: [String])

    /// Honest names for the routine, plain and warm. Warm names say only what the work bears
    /// out: "Steady" for holds and balance, "Strength" for loaded work, never "power".
    func names(for exercises: [Exercise]) -> Names {
        if case let .mobility(region) = self {
            return region.names
        }
        // A real share of stretching, though not most of it, is named alongside the work.
        if exercises.count(where: \.isStretch) * 5 >= exercises.count * 2 {
            if case let .group(group) = self, group != .shoulders {
                return (["\(group.name) and stretch"], [])
            }
            // "Shoulders and stretch" is a character too long.
            return (["Stretch and strength"], [])
        }
        let work = Work(exercises.filter { !$0.isStretch })
        if let implement = work.sharedImplement, let region = implementRegion {
            let name = implement.name
            return region == "full body"
                ? (["\(name) full body"], [])
                : (["\(name) day", "\(name) \(region)"], ["\(name) strength"])
        }
        return workNames(for: work)
    }

    private func workNames(for work: Work) -> Names {
        switch self {
        case let .group(group): group.names(for: work)
        case let .pair(first, second): Self.pairNames(first, second)
        case .push: (["Push day", "Upper body push"], ["Strong push", "Push strength"])
        case .pull: (["Pull day", "Upper body pull"], ["Strong pull", "Pull strength"])
        case .upperBody:
            (["Upper body", "Push and pull"], ["Solid upper body", "Strong upper body"])
        case .upperBodyAndCore: (["Upper body and core"], [])
        case .legsAndCore: (["Legs and core"], ["Strong legs and core"])
        case .fullBody:
            (
                ["Full body", "Total body", "Whole body"],
                work.isAllLoaded
                    ? ["Full body strength", "All-round strength"]
                    : ["Solid full body", "Solid total body"],
            )
        case .mobility: ([], [])
        }
    }

    /// The region a shared implement's name goes with, where one reads well.
    private var implementRegion: String? {
        switch self {
        case .group(.legs), .pair(.legs, _): "legs"
        case .push, .pull, .upperBody: "upper body"
        case .fullBody, .legsAndCore: "full body"
        default: nil
        }
    }

    private static func pairNames(
        _ first: MuscleGroup,
        _ second: MuscleGroup,
    ) -> Names {
        let warm = "Strong \(first.name.lowercased()) and \(second.name.lowercased())"
        return (
            [
                "\(first.name) and \(second.name.lowercased())",
                "\(second.name) and \(first.name.lowercased())",
            ],
            warm.count <= RoutineNamer.longestName ? [warm] : [],
        )
    }
}

/// The exercises that aren't stretches, with what their tags say about them as a whole.
private struct Work {
    let exercises: [Exercise]

    init(_ exercises: [Exercise]) {
        self.exercises = exercises
    }

    /// Whether at least `fraction` of the work is like this.
    func isShare(_ fraction: Double, _ isLike: (Exercise) -> Bool) -> Bool {
        Double(exercises.count(where: isLike)) >= fraction * Double(exercises.count)
    }

    func works(_ muscle: ExerciseTags.Muscle, inShare fraction: Double) -> Bool {
        isShare(fraction) { $0.tags.primary.contains(muscle) }
    }

    /// A barbell or kettlebell every one of two or more exercises uses.
    var sharedImplement: Equipment? {
        guard exercises.count >= 2 else { return nil }
        return [Equipment.barbell, .kettlebell].first { implement in
            exercises.allSatisfy { $0.equipment.contains(implement) }
        }
    }

    /// All strength work under a weight, so "strength" is honest.
    var isAllLoaded: Bool {
        exercises.allSatisfy { exercise in
            exercise.tags.kind == .strength
                && !exercise.equipment.isDisjoint(with: [.dumbbells, .kettlebell, .barbell])
        }
    }
}

extension MuscleGroup {
    fileprivate func names(for work: Work) -> RoutineFocus.Names {
        switch self {
        case .legs: Self.legNames(for: work)
        case .back: Self.backNames(for: work)
        case .chest where work.works(.triceps, inShare: 1 / 2):
            (["Push day", "Chest and triceps"], ["Strong chest", "Strong push"])
        case .chest: (["Push day", "Chest day"], ["Strong chest", "Strong push"])
        case .shoulders: (["Shoulder day"], ["Strong shoulders"])
        case .arms
            where work.works(.biceps, inShare: 1 / 3) && work.works(.triceps, inShare: 1 / 3):
            (["Arm day", "Biceps and triceps"], ["Strong arms"])
        case .arms: (["Arm day"], ["Strong arms"])
        case .core where work.isShare(1 / 2) { $0.tags.movement == .hold }:
            (["Core work", "Core day"], ["Steady core"])
        case .core: (["Core work", "Core day"], ["Strong core", "Steady core"])
        }
    }

    private static func legNames(for work: Work) -> RoutineFocus.Names {
        if work.isShare(1 / 3, { $0.tags.kind == .balance }) {
            return (["Legs and balance"], ["Steady legs"])
        }
        if work.isShare(2 / 3, { $0.tags.movement == .hinge }) {
            return (["Hips and hamstrings"], ["Strong legs"])
        }
        return (["Leg day", "Lower body"], ["Strong legs", "Solid lower body"])
    }

    private static func backNames(for work: Work) -> RoutineFocus.Names {
        if work.works(.forearms, inShare: 1 / 2) {
            return (["Back and grip"], ["Strong back and grip"])
        }
        if work.works(.biceps, inShare: 1 / 2) {
            return (["Back and biceps"], ["Strong back"])
        }
        return (["Pull day", "Back day"], ["Strong back", "Strong pull"])
    }
}

extension RoutineFocus.StretchRegion {
    fileprivate var names: RoutineFocus.Names {
        switch self {
        case .lowerBody:
            (
                ["Hip and leg stretch", "Lower body stretch"],
                ["Easy hip stretch", "Loose hips and legs"],
            )
        case .upperBody: (["Shoulder mobility", "Upper body stretch"], ["Loose shoulders"])
        case .back:
            (["Back stretch", "Back mobility"], ["Easy back stretch", "Gentle back stretch"])
        case .wholeBody:
            (["Full body stretch", "Stretch and mobility"], ["Easy stretch", "Gentle stretch"])
        }
    }
}
