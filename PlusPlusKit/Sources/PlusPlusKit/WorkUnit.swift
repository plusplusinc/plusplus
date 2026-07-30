import Foundation

/// What ONE unit of work is called.
///
/// The app said "set" everywhere until cardio arrived, then grew a
/// `driver == .reps ? "set" : "round"` ternary that got hand-rolled at
/// eight call sites and forgotten at several more — so a distance
/// interval could read `ROUND 3 OF 8` in the kicker, `Log set` on the
/// button and `set 3/8` in the Dynamic Island, three vocabularies for one
/// thing. This type is the single source, and every surface asks it.
///
/// "Round" turned out to be native to none of these sports. Rowers do
/// PIECES (a 4 × 500 m is four pieces); runners and swimmers do REPS
/// (6 × 400 m is "400 repeats", and note that in running "interval"
/// technically names the *recovery*, not the work); cyclists do EFFORTS;
/// lifters do SETS. Walkers and hikers do not do eight of anything, which
/// is why `ExerciseModality.workUnit` is optional.
public struct WorkUnit: Equatable, Sendable {
    public let singular: String
    public let plural: String

    public init(singular: String, plural: String) {
        self.singular = singular
        self.plural = plural
    }

    public static let set = WorkUnit(singular: "set", plural: "sets")
    public static let rep = WorkUnit(singular: "rep", plural: "reps")
    public static let piece = WorkUnit(singular: "piece", plural: "pieces")
    public static let effort = WorkUnit(singular: "effort", plural: "efforts")

    /// `n` of them, pluralized: "1 set", "4 pieces".
    public func counted(_ count: Int) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

    /// The ALL-CAPS kicker over a live effort: "PIECE 3 OF 8".
    ///
    /// ⚠️ nil when `total` is 1. "PIECE 1 OF 1" states nothing you cannot
    /// see, and on a steady forty-minute ride it actively misleads — it
    /// implies a second one is coming. A surface that gets nil renders no
    /// kicker at all rather than substituting a placeholder.
    public static func kicker(_ unit: WorkUnit?, index: Int, total: Int) -> String? {
        guard let unit, total > 1 else { return nil }
        return "\(unit.singular.uppercased()) \(index) OF \(total)"
    }

    /// The lowercase inline form used in captions and up-next lines:
    /// "piece 3". Same nil rule as `kicker`.
    public static func inline(_ unit: WorkUnit?, index: Int, total: Int) -> String? {
        guard let unit, total > 1 else { return nil }
        return "\(unit.singular) \(index)"
    }
}

public extension ExerciseModality {
    /// The noun this family counts in, or nil where counting is not a
    /// thing the sport does. `.strength` and `.flexibility` keep "set",
    /// which is what every lifting surface already says.
    var workUnit: WorkUnit? {
        switch self {
        case .strength, .flexibility: .set
        case .rowing: .piece
        case .running, .swimming, .jumpRope: .rep
        case .cycling, .elliptical, .stairClimbing, .cardio: .effort
        // A walk is a walk. Nobody does eight of them.
        case .walking, .hiking: nil
        }
    }
}
