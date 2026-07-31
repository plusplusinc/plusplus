import Foundation
import Observation
import WatchConnectivity
import PlusPlusKit

/// The wrist side of live mirror (#322). Holds a `LiveSession.Reducer` as
/// the durable working copy of the in-progress workout, emits an op for
/// every wrist action (so the phone sees the run live and can continue it
/// after the watch is set down), and folds in phone ops it receives.
///
/// Durability: the reduced state is journaled to `UserDefaults` after
/// every change, so a run STARTED on the watch with the phone left behind
/// survives the watch app being relaunched — the phone is not here to be
/// the store, so the wrist keeps its own crash-durable copy until contact.
///
/// Confined to the main actor by discipline (WorkoutRunView actions and
/// the store's `Task { @MainActor }` op forwarding) rather than isolation,
/// so `WatchStore` can own it from its non-isolated init.
@Observable
final class WatchLiveSession {
    private static let journalKey = "liveSessionJournal"

    private(set) var reducer = LiveSession.Reducer()
    var state: LiveSession.State? { reducer.state }

    /// The session the WRIST is authoring, frozen at begin. The reducer's
    /// state can be DISPLACED by a newer phone session (#510) while the
    /// run view is still mid-workout, and a wrist log must never land on
    /// a session it didn't come from — reading `state?.sessionId` live
    /// would redirect it. Readable so the finish can stamp the result
    /// payload with the same identity the ops carried (#511).
    private(set) var authoringSessionId: UUID?

    /// Per-origin monotonic sequence (origination = 0).
    private var seq = 0

    init() { restore() }

    // MARK: - Wrist authored

    /// Originates a session for `routine` unless an unfinished one for the
    /// same routine is already in hand (a resume after relaunch, or a
    /// session the phone already started and we adopted).
    func beginIfNeeded(routine: WatchSync.PlanRoutine, startedAt: Date) {
        // isClosed, not isFinished: a discarded session never sets
        // endedAt, and adopting one would log into a dead id (#510).
        // Identity match: the routine's stable uuid when both sides
        // carry one (#511 — names are not unique), the name for older
        // peers.
        if let state, !state.isClosed, Self.matches(state, routine) {
            authoringSessionId = state.sessionId
            return
        }
        reducer = LiveSession.Reducer()
        seq = 0
        let id = UUID()
        authoringSessionId = id
        emit(id, .started(
            routineName: routine.name,
            startedAt: startedAt,
            restSeconds: routine.restSeconds,
            steps: routine.steps,
            routineUuid: routine.uuid
        ))
    }

    private static func matches(_ state: LiveSession.State, _ routine: WatchSync.PlanRoutine) -> Bool {
        if let stateUuid = state.routineUuid, let planUuid = routine.uuid {
            return stateUuid == planUuid
        }
        return state.routineName == routine.name
    }

    func logged(index: Int, weight: Double?, reps: Int?, duration: Int?, extras: [String: Double], at date: Date) {
        guard let id = authoringSessionId else { return }
        emit(id, .logSet(index: index, actualWeight: weight, actualReps: reps, actualDuration: duration, extras: extras, completedAt: date))
    }

    func restStarted(endsAt: Date, total: Int) {
        guard let id = authoringSessionId else { return }
        emit(id, .restStarted(endsAt: endsAt, total: total))
    }

    func restEnded() {
        guard let id = authoringSessionId else { return }
        emit(id, .restEnded)
    }

    func finished(at date: Date) {
        guard let id = authoringSessionId else { return }
        emit(id, .finished(endedAt: date))
        authoringSessionId = nil
    }

    func discarded() {
        guard let id = authoringSessionId else { return }
        emit(id, .discarded)
        authoringSessionId = nil
    }

    // MARK: - Phone authored

    /// Folds a phone op into the wrist's reducer (idempotent) and
    /// rejournals. The phone is the record, so this keeps the wrist's copy
    /// converged.
    func ingest(_ op: LiveSession.Op) {
        reducer.apply(op)
        persist()
        syncRestNotifier(after: op)
    }

    /// Phone-driven rests finally cue the wrist (#511): the "rest over"
    /// notification tracks the phone's rest register — an adjustment
    /// reschedules it, Skip and the session's end cancel it. Wrist-
    /// authored rests are scheduled by the run view itself; this answers
    /// PHONE ops only, and never resurrects a stale rest (a drained
    /// queue can deliver hours-old ops).
    private func syncRestNotifier(after op: LiveSession.Op) {
        guard op.origin == .phone else { return }
        // The wrist's own run owns its notifier: a phone op for a
        // DIFFERENT session (a displaced reducer state — stage 1's
        // authoring freeze exists for exactly this) must not cancel or
        // hijack the pending cue of the rest the wrist user is in.
        guard authoringSessionId == nil || authoringSessionId == op.sessionId else { return }
        switch op.kind {
        case .restStarted, .restEnded, .finished, .discarded:
            guard let state, !state.isClosed,
                  let endsAt = state.restEndsAt, endsAt.timeIntervalSinceNow > 1,
                  let name = Self.upNextName(state) else {
                WatchRestNotifier.cancel()
                return
            }
            WatchRestNotifier.schedule(at: endsAt, exerciseName: name)
        default:
            break
        }
    }

    /// The step the rest is counting down TO — the cursor's step, or the
    /// last one when the cursor has run past the plan. nil only for a
    /// zero-step mirror (a phone scratch session), which has no honest
    /// name to promise.
    private static func upNextName(_ state: LiveSession.State) -> String? {
        if state.steps.indices.contains(state.currentIndex) {
            return state.steps[state.currentIndex].exerciseName
        }
        return state.steps.last?.exerciseName
    }

    // MARK: - Internals

    private func emit(_ sessionId: UUID, _ kind: LiveSession.Kind) {
        seq += 1
        let op = LiveSession.Op(opId: UUID(), sessionId: sessionId, origin: .watch, seq: seq, at: Date(), kind: kind)
        reducer.apply(op)
        persist()
        send(op)
    }

    /// `sendMessage` when the phone is reachable, else the durable
    /// `transferUserInfo` queue so a set logged with the phone in a bag is
    /// delivered when the two next connect.
    private func send(_ op: LiveSession.Op) {
        guard WCSession.isSupported(), let data = try? WatchSync.encode(op) else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            session.transferUserInfo(["liveOp": data]); return
        }
        if session.isReachable {
            session.sendMessage(["liveOp": data], replyHandler: nil) { _ in
                session.transferUserInfo(["liveOp": data])
            }
        } else {
            session.transferUserInfo(["liveOp": data])
        }
    }

    private func persist() {
        // isClosed, not isFinished: a phone discard used to leave the
        // journal in place forever, and the dead state swallowed every
        // future phone session's ops (#510).
        guard let state, !state.isClosed, let data = try? WatchSync.encode(state) else {
            UserDefaults.standard.removeObject(forKey: Self.journalKey)
            return
        }
        UserDefaults.standard.set(data, forKey: Self.journalKey)
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.journalKey),
              let recovered = try? WatchSync.decode(LiveSession.State.self, from: data) else { return }
        reducer.adopt(recovered)
        // Keep the wrist's sequence monotonic across the relaunch.
        seq = recovered.logs.map(\.stamp.seq).max() ?? 0
    }
}
