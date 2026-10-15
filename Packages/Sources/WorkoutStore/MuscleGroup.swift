/// The body part an exercise mostly works. Each exercise has one.
///
/// Cases are declared from the top of the body down, which is the order a routine's groups are
/// named in.
public enum MuscleGroup: CaseIterable, Sendable {
    case chest
    case back
    case shoulders
    case arms
    case legs
    case core

    public var name: String {
        switch self {
        case .chest: "Chest"
        case .back: "Back"
        case .shoulders: "Shoulders"
        case .arms: "Arms"
        case .legs: "Legs"
        case .core: "Core"
        }
    }

    /// A routine's name from the groups its exercises work: "Legs" for one, "Chest and back" for
    /// two, "Full body" for more, and nil for none. Named in declaration order, not the order
    /// exercises were added, so adding one never reshuffles the name.
    public static func routineName(for groups: some Sequence<Self>) -> String? {
        let present = Set(groups)
        let named = allCases.filter(present.contains).map(\.name)
        switch named.count {
        case 0:
            return nil
        case 1:
            return named[0]
        case 2:
            return "\(named[0]) and \(named[1].lowercased())"
        default:
            return "Full body"
        }
    }
}
