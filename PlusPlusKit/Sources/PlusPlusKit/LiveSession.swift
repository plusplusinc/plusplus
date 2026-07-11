import Foundation

/// The live-mirror core (#322): an in-progress workout modeled as an
/// append-only log of `Op`s that EITHER device can emit and BOTH reduce
/// to an identical `State`. Pure and Linux-tested, so the phone and watch
/// adapters stay thin.
///
/// Model — the iPhone is the durable system of record, but CUSTODY is
/// mobile: either device can ORIGINATE a session (mint the `sessionId`
/// via a `.started` op that carries the plan) and be its sole author
/// while the other is absent (a run with the phone left behind). On
/// contact the logs merge. There is one human, so custody is HANDED OFF,
/// never split — a per-field last-writer-wins register suffices, no CRDT
/// machinery.
///
/// Convergence: every mutable field carries a `Stamp` (`at`, `origin`,
/// `seq`); the higher stamp wins, the phone breaking wall-clock ties (it
/// is the record). `apply(op)` and `merge(state)` are both commutative
/// and idempotent, so the same set of ops — in any delivery order, with
/// duplicates, from a device that was offline — reduces to the same
/// `State` on both sides.
public enum LiveSession {

    public enum Origin: String, Codable, Equatable, Sendable {
        case phone, watch
    }

    /// LWW ordering key. Later `at` wins; the phone breaks wall-clock
    /// ties (it is the durable record); `seq` breaks same-origin ties.
    public struct Stamp: Codable, Equatable, Sendable, Comparable {
        public var at: Date
        public var origin: Origin
        public var seq: Int

        public init(at: Date, origin: Origin, seq: Int) {
            self.at = at
            self.origin = origin
            self.seq = seq
        }

        public static func < (a: Stamp, b: Stamp) -> Bool {
            if a.at != b.at { return a.at < b.at }
            // Equal instant: phone outranks watch.
            if a.origin != b.origin { return a.origin == .watch }
            return a.seq < b.seq
        }
    }

    /// One mutation to an in-progress session. Idempotent by `opId`;
    /// `seq` is a per-origin monotonic counter (origination = 0).
    public struct Op: Codable, Equatable, Sendable, Identifiable {
        public var opId: UUID
        public var sessionId: UUID
        public var origin: Origin
        public var seq: Int
        public var at: Date
        public var kind: Kind

        public var id: UUID { opId }

        public var stamp: Stamp { Stamp(at: at, origin: origin, seq: seq) }

        public init(opId: UUID, sessionId: UUID, origin: Origin, seq: Int, at: Date, kind: Kind) {
            self.opId = opId
            self.sessionId = sessionId
            self.origin = origin
            self.seq = seq
            self.at = at
            self.kind = kind
        }
    }

    public enum Kind: Codable, Equatable, Sendable {
        /// Session birth. Carries the plan so a watch-originated session
        /// can materialize on a phone that never saw it. `steps` are in
        /// execution order (supersets already rotated); `restSeconds` is
        /// the routine default.
        case started(routineName: String, startedAt: Date, restSeconds: Int, steps: [WatchSync.Step])
        /// A set logged (or re-logged) at `index`.
        case logSet(index: Int, actualWeight: Double?, actualReps: Int?, actualDuration: Int?, extras: [String: Double], completedAt: Date)
        /// A logged set reopened (redo) — clears its actuals/completion.
        case reopen(index: Int)
        /// Rest began, draining to `endsAt` over `total` seconds.
        case restStarted(endsAt: Date, total: Int)
        /// Rest ended (skip / natural expiry / moved on).
        case restEnded
        /// The active cursor moved (jump/redo navigation).
        case cursor(index: Int)
        /// Session finished at `endedAt`.
        case finished(endedAt: Date)
        /// Session discarded (the record is deleted).
        case discarded
    }

    /// One logged set inside the reduced state.
    public struct LoggedSet: Codable, Equatable, Sendable {
        public var index: Int
        public var actualWeight: Double?
        public var actualReps: Int?
        public var actualDuration: Int?
        public var extras: [String: Double]
        public var completedAt: Date?
        /// Ordering stamp of the op that last wrote this slot, for LWW.
        public var stamp: Stamp

        public init(index: Int, actualWeight: Double? = nil, actualReps: Int? = nil, actualDuration: Int? = nil, extras: [String: Double] = [:], completedAt: Date? = nil, stamp: Stamp) {
            self.index = index
            self.actualWeight = actualWeight
            self.actualReps = actualReps
            self.actualDuration = actualDuration
            self.extras = extras
            self.completedAt = completedAt
            self.stamp = stamp
        }
    }

    /// The reduced live state — what both devices render, and what the
    /// phone projects into SwiftData at checkpoints/finish. Self-describes
    /// its op coverage via `applied`, so a snapshot merges cleanly with a
    /// peer that holds not-yet-seen local ops.
    public struct State: Codable, Equatable, Sendable {
        public var sessionId: UUID
        /// Which device minted the session.
        public var origin: Origin
        public var routineName: String
        public var startedAt: Date
        public var restSeconds: Int
        public var steps: [WatchSync.Step]
        public var logs: [LoggedSet]
        public var cursor: Int
        public var cursorStamp: Stamp?
        public var restEndsAt: Date?
        public var restTotal: Int
        public var restStamp: Stamp?
        public var endedAt: Date?
        public var discarded: Bool
        public var lifecycleStamp: Stamp?
        /// opIds folded in — a grow-only set, so coverage compares
        /// order-independently and criss-cross merges converge.
        public var applied: Set<UUID>

        /// Births a state from a `.started` op.
        public init?(started op: Op) {
            guard case let .started(routineName, startedAt, restSeconds, steps) = op.kind else { return nil }
            self.sessionId = op.sessionId
            self.origin = op.origin
            self.routineName = routineName
            self.startedAt = startedAt
            self.restSeconds = restSeconds
            self.steps = steps
            self.logs = []
            self.cursor = 0
            self.cursorStamp = nil
            self.restEndsAt = nil
            self.restTotal = 0
            self.restStamp = nil
            self.endedAt = nil
            self.discarded = false
            self.lifecycleStamp = nil
            self.applied = [op.opId]
        }

        // MARK: Derived

        public var totalSteps: Int { steps.count }
        public var completedCount: Int { logs.filter { $0.completedAt != nil }.count }
        public var isFinished: Bool { endedAt != nil }
        public var isResting: Bool { restEndsAt != nil }

        public func log(at index: Int) -> LoggedSet? {
            logs.first { $0.index == index }
        }

        /// First step with no completed log, or `totalSteps` if all done.
        public var firstIncompleteIndex: Int {
            for i in 0..<steps.count where log(at: i)?.completedAt == nil { return i }
            return steps.count
        }

        /// The step the user is on: an explicit cursor move wins, else the
        /// first incomplete step (mirrors the phone's `currentLog`).
        public var currentIndex: Int {
            cursorStamp != nil ? cursor : firstIncompleteIndex
        }

        // MARK: Mutation

        /// Folds one op in. Idempotent (a seen `opId` is a no-op); each
        /// field resolves last-writer-wins by stamp. Returns whether the
        /// state changed.
        @discardableResult
        public mutating func apply(_ op: Op) -> Bool {
            guard sessionId == op.sessionId else { return false }
            guard !applied.contains(op.opId) else { return false }
            applied.insert(op.opId)
            let stamp = op.stamp
            switch op.kind {
            case .started:
                break // identity already established
            case let .logSet(index, w, r, d, extras, completedAt):
                replaceLog(LoggedSet(index: index, actualWeight: w, actualReps: r, actualDuration: d, extras: extras, completedAt: completedAt, stamp: stamp))
            case let .reopen(index):
                replaceLog(LoggedSet(index: index, stamp: stamp))
            case let .restStarted(endsAt, total):
                if Self.beats(stamp, restStamp) { restEndsAt = endsAt; restTotal = total; restStamp = stamp }
            case .restEnded:
                if Self.beats(stamp, restStamp) { restEndsAt = nil; restStamp = stamp }
            case let .cursor(index):
                if Self.beats(stamp, cursorStamp) { cursor = index; cursorStamp = stamp }
            case let .finished(endedAt):
                if Self.beats(stamp, lifecycleStamp) { self.endedAt = endedAt; discarded = false; lifecycleStamp = stamp }
            case .discarded:
                if Self.beats(stamp, lifecycleStamp) { discarded = true; lifecycleStamp = stamp }
            }
            return true
        }

        /// Joins a peer state (LWW per field, union of applied). Both
        /// commutative and idempotent, so repeated/criss-cross merges
        /// converge.
        public mutating func merge(_ other: State) {
            guard sessionId == other.sessionId else { return }
            for ol in other.logs { replaceLog(ol) }
            if Self.beats(other.restStamp, restStamp) {
                restEndsAt = other.restEndsAt; restTotal = other.restTotal; restStamp = other.restStamp
            }
            if Self.beats(other.cursorStamp, cursorStamp) {
                cursor = other.cursor; cursorStamp = other.cursorStamp
            }
            if Self.beats(other.lifecycleStamp, lifecycleStamp) {
                endedAt = other.endedAt; discarded = other.discarded; lifecycleStamp = other.lifecycleStamp
            }
            applied.formUnion(other.applied)
        }

        private mutating func replaceLog(_ candidate: LoggedSet) {
            if let i = logs.firstIndex(where: { $0.index == candidate.index }) {
                if candidate.stamp > logs[i].stamp { logs[i] = candidate }
            } else {
                logs.append(candidate)
                logs.sort { $0.index < $1.index }
            }
        }

        /// `a` outranks `b` when `a` exists and is strictly greater (or
        /// `b` is absent). A nil challenger never wins.
        private static func beats(_ a: Stamp?, _ b: Stamp?) -> Bool {
            guard let a else { return false }
            guard let b else { return true }
            return a > b
        }
    }

    // MARK: - Reducer

    /// Stateful folder that materializes a `State` from a stream of ops
    /// arriving in any order. Ops seen before the session's `.started`
    /// (out-of-order delivery) are buffered and replayed once identity
    /// exists.
    public struct Reducer {
        public private(set) var state: State?
        private var pending: [Op] = []

        public init() {}

        public mutating func apply(_ op: Op) {
            if state != nil {
                state?.apply(op)
            } else if let born = State(started: op) {
                state = born
                let buffered = pending
                pending = []
                for p in buffered { apply(p) }
            } else {
                pending.append(op)
            }
        }

        /// Adopts an authoritative peer snapshot: merges if it's the same
        /// session, otherwise takes it as the base and replays any pending
        /// ops (the phone-born session a joining watch first learns of).
        public mutating func adopt(_ snapshot: State) {
            if state?.sessionId == snapshot.sessionId {
                state?.merge(snapshot)
            } else {
                state = snapshot
                let buffered = pending
                pending = []
                for p in buffered { apply(p) }
            }
        }
    }

    /// One-shot reduction of an op set — order-independent by construction.
    public static func reduce(_ ops: [Op]) -> State? {
        var reducer = Reducer()
        for op in ops { reducer.apply(op) }
        return reducer.state
    }
}
