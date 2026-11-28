import Foundation

/// One message between the phone and the Watch over the mirrored workout session's link, as
/// JSON. The Watch sends what the wrist did, numbered (`LinkAction`); the phone, the one that
/// stores the workout, sends the workout as it stands (`LinkState`), so a state heard twice or
/// late changes nothing, and a reconnect needs only each side's "here is what I hold".
public struct LinkMessage: Codable, Equatable, Sendable {
    /// The wire's version: a message of another is dropped. The two apps install together, so
    /// a mismatch lasts only between two installs.
    public static let version = 1

    public enum Body: Codable, Equatable, Sendable {
        /// Sent by the phone as a mirrored session is handed to it, until the Watch answers;
        /// answered by the Watch with its own hello and the actions it holds, and by the phone
        /// with a full state.
        case hello
        case actions([LinkAction])
        case state(LinkState)
        /// The phone's workout is over, or it runs none: its answer to a message for a session
        /// it does not hold.
        case ended(LinkEnd)
    }

    public var wire: Int
    /// The workout session it is about (`WorkoutSession.id`); one for another is dropped.
    public var session: UUID
    public var body: Body

    public init(session: UUID, body: Body) {
        wire = Self.version
        self.session = session
        self.body = body
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// The message in `data`, or nil for one that does not decode or is another version's.
    public static func decoded(from data: Data) -> Self? {
        guard let message = try? JSONDecoder().decode(Self.self, from: data),
              message.wire == version
        else { return nil }
        return message
    }
}

/// Something the wrist did, numbered from 1 within its workout session. The Watch keeps it until
/// a state confirms it (`LinkState.watchSeq`); the phone applies each above the highest it has
/// applied, in order, at its own `at`, so a rest starts where the wrist tapped however late the
/// phone hears.
public struct LinkAction: Codable, Equatable, Sendable {
    public var seq: Int
    public var at: Date
    public var action: WireAction

    public init(seq: Int, at: Date, action: WorkoutAction) {
        self.seq = seq
        self.at = at
        self.action = WireAction(action)
    }
}

/// The phone's workout as it stands. `rev` rises with every one it sends, and the Watch keeps
/// only the highest; `watchSeq` is the highest Watch action in it. The plan rides along after a
/// (re)connect and after an edit to the workout; otherwise the Watch keeps the last one.
public struct LinkState: Codable, Equatable, Sendable {
    public var rev: Int
    public var watchSeq: Int
    public var plan: WirePlan?
    public var session: WireSession

    public init(rev: Int, watchSeq: Int, plan: Workout?, session: WorkoutSession) {
        self.rev = rev
        self.watchSeq = watchSeq
        self.plan = plan.map(WirePlan.init)
        self.session = WireSession(session)
    }
}

/// How the phone's workout ended, for the Watch's last page.
public struct LinkEnd: Codable, Equatable, Sendable {
    /// Finished and kept; false for discarded, or none running.
    public var finished: Bool
    public var name: String
    public var sets: Int
    public var elapsed: Double

    public init(finished: Bool, name: String, sets: Int, elapsed: Double) {
        self.finished = finished
        self.name = name
        self.sets = sets
        self.elapsed = elapsed
    }

    /// `session` as it ended at `date`; nil `session` for one discarded or not running.
    public init(_ session: WorkoutSession?, at date: Date) {
        finished = session?.endedAt != nil
        name = session?.workoutName ?? ""
        sets = session?.sets.count ?? 0
        elapsed = session.map { Double($0.elapsed(at: date).components.seconds) } ?? 0
    }
}
