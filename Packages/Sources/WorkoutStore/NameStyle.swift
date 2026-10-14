import Foundation

/// How a routine's generated name is worded, fixed by the routine's id: the same routine keeps
/// its style as its exercises change, and different routines differ.
struct NameStyle: Equatable {
    /// About one routine in three gets a name with some character; the rest get a plain label.
    let hasCharacter: Bool
    /// Which of a focus's names the routine takes. Up to 60, so it spreads evenly over a list of
    /// any length up to six.
    let variant: Int

    init(of routine: UUID) {
        // From the id's own bytes, not `hashValue`, which changes from launch to launch.
        let bytes = withUnsafeBytes(of: routine.uuid) { Array($0.prefix(8)) }
        let seed = bytes.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        hasCharacter = seed.isMultiple(of: 3)
        variant = Int(seed / 3 % 60)
    }

    /// The routine's pick of the names: one with character when the routine has it and the
    /// focus offers one.
    func pick(_ names: RoutineFocus.Names) -> String? {
        let options = hasCharacter && !names.character.isEmpty ? names.character : names.plain
        return options.isEmpty ? nil : options[variant % options.count]
    }
}

extension RoutineFocus {
    /// A focus's names: plain labels, and names with a touch of character, which a routine's
    /// style picks from.
    typealias Names = (plain: [String], character: [String])

    /// Honest names for the routine, in the product's voice. Character comes from the word, not
    /// from a structure: an image ("Heavy legs"), how lifters say it ("Back and bis"), a mood
    /// ("Unwind"), understatement ("Odds and ends"), the equipment ("Barbell day"), or the work
    /// itself ("Hold still"). Each says only what the tags bear out: "Heavy" only under a
    /// weight, "Under the bar" only for barbell squats.
    func names(for exercises: [Exercise]) -> Names {
        if case let .mobility(region) = self {
            return region.names(for: exercises.filter(\.isStretch))
        }
        let work = Work(exercises.filter { !$0.isStretch })
        // A real share of stretching, though not most of it, is named alongside the work.
        if exercises.count(where: \.isStretch) * 5 >= exercises.count * 2 {
            return stretchAndWorkNames(for: work)
        }
        if let implement = work.sharedImplement, let region = implementRegion {
            return Self.implementNames(implement, region, for: work)
        }
        return workNames(for: work)
    }

    private func stretchAndWorkNames(for work: Work) -> Names {
        let lift = work.isAllLoaded ? ["Lift and stretch"] : []
        // "Shoulders and stretch" is a character too long.
        if case let .group(group) = self, group != .shoulders {
            return (["\(group.name) and stretch"], lift)
        }
        return (["Stretch and strength"], lift + ["A bit of both"])
    }

    private func workNames(for work: Work) -> Names {
        switch self {
        case let .group(group): group.names(for: work)
        case let .pair(first, second): Self.pairNames(first, second, for: work)
        case .push:
            (
                ["Push day", "Upper body push"]
                    + (work.spans(.chest, .shoulders) ? ["Chest and shoulders"] : []),
                work.isShare(2 / 3, \.isPress) ? ["Press day"] : ["Push"],
            )
        case .pull:
            (
                ["Pull day", "Upper body pull"],
                work.spans(.back) && work.works(.biceps, inShare: 0) ? ["Back and bis"] : ["Pull"],
            )
        case .upperBody: (["Upper body", "Push and pull"], ["Top half"])
        case .upperBodyAndCore: (["Upper body and core", "Core and upper body"], ["Top half"])
        case .legsAndCore: Self.pairNames(.legs, .core, for: work)
        case .fullBody: Self.fullBodyNames(for: work)
        case .mobility: ([], [])
        }
    }

    private static func fullBodyNames(for work: Work) -> Names {
        var character = ["Head to toe"]
        if work.isAllLoaded {
            character.append("Lift everything")
        } else if work.isOneOfEach {
            character.append("Odds and ends")
        }
        return (["Full body", "Total body", "Whole body"], character)
    }

    /// The barbell five: squat, bench, row, press, deadlift.
    private static let bigFive: Set<Exercise.ID> = [
        "barbell-back-squat",
        "barbell-bench-press",
        "barbell-row",
        "barbell-overhead-press",
        "barbell-deadlift",
    ]

    private static func implementNames(
        _ implement: Equipment,
        _ region: String,
        for work: Work,
    ) -> Names {
        let plain = ["\(implement.name) \(region)"]
        guard implement == .barbell else { return (plain, ["\(implement.name) day"]) }
        if Set(work.exercises.map(\.id)) == bigFive {
            return (plain, ["The big five"])
        }
        let squats = region == "legs" && work.moves(.squat, inShare: 1 / 2)
        return (plain, ["Barbell day"] + (squats ? ["Under the bar"] : []))
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

    /// Groups pair in declaration order, so legs come after the upper body and core after both.
    private static func pairNames(
        _ first: MuscleGroup,
        _ second: MuscleGroup,
        for work: Work,
    ) -> Names {
        var plain = [
            "\(first.name) and \(second.name.lowercased())",
            "\(second.name) and \(first.name.lowercased())",
        ]
        var character: [String] = []
        switch (first, second) {
        case (.legs, .core): plain.append("Lower body and core")
        case (_, .legs):
            plain.append("Upper and lower")
            character = work.isAllLoaded ? ["Heavy day"] : []
        default: character = ["Top half"]
        }
        return (plain, character)
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

    /// Whether at least `fraction` of the work has the muscle first; a fraction of zero asks
    /// whether any does.
    func works(_ muscle: ExerciseTags.Muscle, inShare fraction: Double) -> Bool {
        let count = exercises.count { $0.tags.primary.contains(muscle) }
        return count > 0 && Double(count) >= fraction * Double(exercises.count)
    }

    func moves(_ movement: ExerciseTags.Movement, inShare fraction: Double) -> Bool {
        isShare(fraction) { $0.tags.movement == movement }
    }

    /// Whether every one of these groups has work in it.
    func spans(_ groups: MuscleGroup...) -> Bool {
        groups.allSatisfy { group in exercises.contains { $0.muscleGroup == group } }
    }

    /// A barbell or kettlebell every one of two or more exercises uses.
    var sharedImplement: Equipment? {
        guard exercises.count >= 2 else { return nil }
        return [Equipment.barbell, .kettlebell].first { implement in
            exercises.allSatisfy { $0.equipment.contains(implement) }
        }
    }

    /// All strength work under a weight, so "heavy" is honest.
    var isAllLoaded: Bool {
        exercises.allSatisfy { $0.tags.kind == .strength && $0.isLoaded }
    }

    var isAllBodyweight: Bool {
        !exercises.contains(where: \.isLoaded)
    }

    /// No two exercises for the same group: a grab bag.
    var isOneOfEach: Bool {
        Set(exercises.map(\.muscleGroup)).count == exercises.count
    }
}

extension Exercise {
    fileprivate var isLoaded: Bool {
        !equipment.isDisjoint(with: [.dumbbells, .kettlebell, .barbell])
    }

    /// A weight pushed away with the chest or shoulders: a bench or overhead press, not a
    /// push-up or a triceps extension.
    fileprivate var isPress: Bool {
        tags.movement == .push && isLoaded && !tags.primary.isDisjoint(with: [.chest, .frontDelts])
    }

    /// A pull into the upper back, not a pull-up.
    fileprivate var isRow: Bool {
        tags.movement == .pull && tags.primary.contains(.upperBack)
    }
}

extension MuscleGroup {
    fileprivate func names(for work: Work) -> RoutineFocus.Names {
        switch self {
        case .legs: Self.legNames(for: work)
        case .back: Self.backNames(for: work)
        case .chest: Self.chestNames(for: work)
        case .shoulders: (["Shoulder day"], work.moves(.push, inShare: 2 / 3) ? ["Overhead"] : [])
        case .arms: Self.armNames(for: work)
        case .core: Self.coreNames(for: work)
        }
    }

    private static func legNames(for work: Work) -> RoutineFocus.Names {
        if work.isShare(1 / 3, { $0.tags.kind == .balance }) {
            return (["Legs and balance", "Balance and legs"], ["Steady legs"])
        }
        if work.moves(.hinge, inShare: 2 / 3) {
            // Hamstrings only when they do the work first: a glute bridge is a glute day.
            let plain = work.works(.hamstrings, inShare: 0) ? "Hips and hamstrings" : "Glute day"
            return ([plain, "Leg day"], ["Bend and lift"])
        }
        return (
            ["Leg day", "Lower body"],
            [work.isAllLoaded ? "Heavy legs" : "Stairs tomorrow", "Just legs"],
        )
    }

    private static func backNames(for work: Work) -> RoutineFocus.Names {
        if work.works(.forearms, inShare: 1 / 2) {
            return (["Back and grip"], ["Hang time"])
        }
        if work.works(.biceps, inShare: 1 / 2) {
            return (["Back and biceps"], ["Back and bis"])
        }
        let character = if work.exercises.allSatisfy({ $0.equipment.contains(.pullUpBar) }) {
            "On the bar"
        } else if work.exercises.allSatisfy(\.isRow) {
            "Rows"
        } else {
            "Back at it"
        }
        return (["Back day", "Pull day"], [character])
    }

    private static func chestNames(for work: Work) -> RoutineFocus.Names {
        if work.works(.triceps, inShare: 1 / 2) {
            return (
                ["Chest and triceps", "Push day", "Chest day"],
                work.isAllBodyweight ? ["No weights"] : [],
            )
        }
        let benches = work.exercises.allSatisfy { $0.isPress && $0.equipment.contains(.bench) }
        let character = benches ? ["Bench day"] : work
            .isShare(2 / 3, \.isPress) ? ["Press day"] : []
        return (["Chest day", "Push day"], character)
    }

    private static func armNames(for work: Work) -> RoutineFocus.Names {
        if work.works(.biceps, inShare: 1 / 3), work.works(.triceps, inShare: 1 / 3) {
            return (["Arm day", "Biceps and triceps"], ["Curls and extensions"])
        }
        return (["Arm day"], work.works(.biceps, inShare: 2 / 3) ? ["Curls"] : [])
    }

    private static func coreNames(for work: Work) -> RoutineFocus.Names {
        let plain = ["Core work", "Core day"]
        if work.moves(.hold, inShare: 1 / 2) {
            return (plain, ["Hold still", "Steady core"])
        }
        return (plain, ["Brace"])
    }
}

extension RoutineFocus.StretchRegion {
    /// Names that say only where the stretches reach: a calf stretch opens no hips, and a chest
    /// stretch alone is no shoulder stretch.
    fileprivate func names(for stretches: [Exercise]) -> RoutineFocus.Names {
        switch self {
        case .lowerBody:
            let hips = stretches.contains {
                !$0.tags.primary.isDisjoint(with: [.glutes, .hipFlexors])
            }
            return hips
                ? (["Hip and leg stretch", "Lower body stretch"], ["Hip opener", "Slow stretch"])
                : (["Leg stretch", "Lower body stretch"], ["Stretch the legs"])
        case .upperBody:
            let shoulders = stretches.contains { $0.muscleGroup == .shoulders }
            return (
                ["Upper body stretch"] + (shoulders ? ["Shoulder stretch"] : []),
                ["Open up"] + (shoulders ? ["Loose shoulders"] : []),
            )
        case .back:
            return (["Back stretch", "Back mobility"], ["Loosen the back"])
        case .wholeBody:
            return (["Full body stretch", "Stretch and mobility"], ["Unwind", "Stretch it out"])
        }
    }
}
