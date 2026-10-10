/// A piece of kit an exercise uses. An exercise with none is bodyweight.
///
/// Cases are declared in display order, which is the order an exercise's equipment is listed
/// in. Raw values are the stable strings storage will use, so a renamed display name never
/// orphans saved data.
public enum Equipment: String, CaseIterable, Sendable {
    case dumbbells
    case kettlebell
    case barbell
    case bench
    case band
    case pullUpBar
    case rings
    case balanceBoard

    public var name: String {
        switch self {
        case .dumbbells: "Dumbbells"
        case .kettlebell: "Kettlebell"
        case .barbell: "Barbell"
        case .bench: "Bench"
        case .band: "Band"
        case .pullUpBar: "Pull-up bar"
        case .rings: "Rings"
        case .balanceBoard: "Balance board"
        }
    }
}
