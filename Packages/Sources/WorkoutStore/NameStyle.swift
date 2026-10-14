import Foundation

/// How a routine's generated name is worded, fixed by the routine's id: the same routine keeps
/// its style as its exercises change, and different routines differ.
struct NameStyle: Equatable {
    /// About one routine in three gets a lightly positive name; the rest stay plain.
    let isWarm: Bool
    /// Which of a focus's example names the routine is pointed at.
    let variant: Int

    init(of routine: UUID) {
        // From the id's own bytes, not `hashValue`, which changes from launch to launch.
        let bytes = withUnsafeBytes(of: routine.uuid) { Array($0.prefix(8)) }
        let seed = bytes.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        isWarm = seed.isMultiple(of: 3)
        variant = Int(seed / 3 % 6)
    }
}

extension RoutineFocus {
    /// The names the model picks from: honest for the focus, in the routine's tone, led by the
    /// one its variant points at, so names vary across routines but hold within one.
    func candidates(style: NameStyle, endsWithStretching: Bool) -> [String] {
        let options = style.isWarm ? examples.warm : examples.plain
        let shift = style.variant % options.count
        var names = Array(options[shift...] + options[..<shift])
        if endsWithStretching, case let .group(group) = self {
            names.append("\(group.name) and stretch")
        }
        return names
    }

    /// The same names for both tones, where no warm one reads well.
    private static func both(_ names: [String]) -> (plain: [String], warm: [String]) {
        (names, names)
    }

    private var examples: (plain: [String], warm: [String]) {
        switch self {
        case .mobility:
            (
                ["Stretch and mobility", "Mobility", "Stretch and reset"],
                ["Easy stretch", "Fresh stretch"],
            )
        case let .group(group):
            group.examples
        case let .pair(first, second):
            Self.both([
                "\(first.name) and \(second.name.lowercased())",
                "\(second.name) and \(first.name.lowercased())",
            ])
        case .push: (["Push day", "Upper body push"], ["Push power", "Push strength"])
        case .pull: (["Pull day", "Upper body pull"], ["Pull power", "Strong pull"])
        case .upperBody: (
                ["Upper body", "Push and pull"],
                ["Solid upper body", "Strong upper body"],
            )
        case .upperBodyAndCore: Self.both(["Upper body and core"])
        case .legsAndCore: (["Legs and core"], ["Strong legs and core"])
        case .fullBody:
            (
                ["Full body", "Total body", "Whole body"],
                ["Full body strength", "Total body power", "All-round strength"],
            )
        }
    }
}

extension MuscleGroup {
    fileprivate var examples: (plain: [String], warm: [String]) {
        switch self {
        case .chest: (["Push day", "Chest day"], ["Push power", "Strong chest"])
        case .back: (["Pull day", "Back day"], ["Pull power", "Strong back"])
        case .shoulders: (["Shoulder day"], ["Strong shoulders"])
        case .arms: (["Arm day"], ["Strong arms", "Arm power"])
        case .legs: (["Leg day", "Lower body"], ["Strong legs", "Leg power"])
        case .core: (["Core work", "Core day"], ["Steady core", "Strong core"])
        }
    }
}
