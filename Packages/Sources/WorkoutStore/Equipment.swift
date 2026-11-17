/// A piece of kit an exercise uses. An exercise with none is bodyweight.
///
/// Cases are declared in display order, which is the order an exercise's equipment is listed
/// in. Raw values are what a created exercise stores, written out so renaming a case never
/// changes stored data.
public enum Equipment: String, CaseIterable, Sendable {
    case dumbbells
    case kettlebell
    case barbell
    case medicineBall = "medicine-ball"
    case bench
    case band
    case pullUpBar = "pull-up-bar"
    case rings
    case balanceBoard = "balance-board"

    public var name: String {
        switch self {
        case .dumbbells: "Dumbbells"
        case .kettlebell: "Kettlebell"
        case .barbell: "Barbell"
        case .medicineBall: "Medicine ball"
        case .bench: "Bench"
        case .band: "Band"
        case .pullUpBar: "Pull-up bar"
        case .rings: "Rings"
        case .balanceBoard: "Balance board"
        }
    }
}
