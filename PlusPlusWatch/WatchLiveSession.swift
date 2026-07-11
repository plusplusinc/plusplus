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

    /// Per-origin monotonic sequence (origination = 0).
    private var seq = 0

    init() { restore() }

    // MARK: - Wrist authored

    /// Originates a session for `routine` unless an unfinished one for the
    /// same routine is already in hand (a resume after relaunch, or a
    /// session the phone already started and we adopted).
    func beginIfNeeded(routine: WatchSync.PlanRoutine, startedAt: Date) {
        if let state, !state.isFinished, state.routineName == routine.name { return }
        reducer = LiveSession.Reducer()
        seq = 0
        emit(UUID(), .started(
            routineName: routine.name,
            startedAt: startedAt,
            restSeconds: routine.restSeconds,
            steps: routine.steps
        ))
    }

    func logged(index: Int, weight: Double?, reps: Int?, duration: Int?, extras: [String: Double], at date: Date) {
        guard let id = state?.sessionId else { return }
        emit(id, .logSet(index: index, actualWeight: weight, actualReps: reps, actualDuration: duration, extras: extras, completedAt: date))
    }

    func restStarted(endsAt: Date, total: Int) {
        guard let id = state?.sessionId else { return }
        emit(id, .restStarted(endsAt: endsAt, total: total))
    }

    func restEnded() {
        guard let id = state?.sessionId else { return }
        emit(id, .restEnded)
    }

    func finished(at date: Date) {
        guard let id = state?.sessionId else { return }
        emit(id, .finished(endedAt: date))
    }

    func discarded() {
        guard let id = state?.sessionId else { return }
        emit(id, .discarded)
    }

    // MARK: - Phone authored

    /// Folds a phone op into the wrist's reducer (idempotent) and
    /// rejournals. The phone is the record, so this keeps the wrist's copy
    /// converged.
    func ingest(_ op: LiveSession.Op) {
        reducer.apply(op)
        persist()
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
        guard let state, !state.isFinished, let data = try? WatchSync.encode(state) else {
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
