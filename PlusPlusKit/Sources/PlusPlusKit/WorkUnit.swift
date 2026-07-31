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
    /// Boxing's word, and the one place it IS native: a jump-rope or bag
    /// bout is a round. Deliberately not `.rep` — "Reps: 3" on a
    /// 3 × 60 s skipping block reads as three skips, colliding with the
    /// meaning reps carry everywhere else in the app.
    public static let round = WorkUnit(singular: "round", plural: "rounds")

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

public extension WorkUnit {
    /// What to call the control that DIVIDES an effort, for a sport that
    /// counts nothing of its own.
    ///
    /// A walk has no "sets" — that is the whole point of `workUnit` being
    /// nil there — but the control still has to say something, because a
    /// hill repeat is a real thing to author even where one continuous
    /// effort is the honest default. "Rounds" is the sport-neutral word the
    /// app already owns (jump rope counts in them), so the control keeps
    /// the capability without borrowing the rack's noun. Before this, both
    /// prescription sheets fell back to `.set` and offered to give a walk
    /// three sets.
    ///
    /// ⚠️ For the DIVIDER only. The kicker, the inline caption and the
    /// commit key keep the nil and print nothing at all — a walk still says
    /// "Log", never "Log round", and shows no `ROUND 1 OF 1`.
    static func divider(_ unit: WorkUnit?) -> WorkUnit { unit ?? .round }

    /// How much work a finished session claims on its card and in its
    /// header: "18 sets", "6 reps", "3 rounds" — and NOTHING at a count of
    /// one.
    ///
    /// `kicker`'s rule, one surface later. A steady forty-minute walk is
    /// not "1 set"; it is not "1 round" either. It is one continuous thing,
    /// and the honest subtitle names the date and the duration and stops.
    /// Above one the divider's noun applies, because a count above one is
    /// precisely what the divider authored.
    static func summaryCount(_ unit: WorkUnit?, _ count: Int) -> String? {
        guard count > 1 else { return nil }
        return divider(unit).counted(count)
    }

    /// The label on ONE row of a finished record — "Set 3", "Round 2" —
    /// and NOTHING when the record holds a single row.
    ///
    /// ⚠️ The one place a nil unit still earns the divider's noun mid-list,
    /// and the reason is the list: a row has siblings to be told apart
    /// from, where the live caption describes the single thing in front of
    /// you. Both agree on the case that matters — at one there is no label.
    static func rowLabel(_ unit: WorkUnit?, index: Int, total: Int) -> String? {
        guard total > 1 else { return nil }
        return "\(divider(unit).singular.capitalized) \(index)"
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
        case .running, .swimming: .rep
        case .jumpRope: .round
        case .cycling, .elliptical, .stairClimbing, .cardio: .effort
        // A walk is a walk. Nobody does eight of them.
        case .walking, .hiking: nil
        }
    }
}
