import Foundation
import Observation
import WatchConnectivity
import PlusPlusKit

/// The wrist's whole data layer (#6): the latest plan pushed from the
/// phone (cached in UserDefaults so the list survives relaunches with
/// the phone out of reach) and the outbox for finished sessions.
/// No SwiftData on the watch — the phone owns storage.
@Observable
final class WatchStore: NSObject, WCSessionDelegate {
    static let planDefaultsKey = "cachedPlan"

    private(set) var plan: WatchSync.Plan?

    /// The live-mirror working copy (#322): emits wrist ops to the phone,
    /// folds in phone ops, and journals the in-progress session.
    let live = WatchLiveSession()

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: Self.planDefaultsKey),
           let cached = try? WatchSync.decode(WatchSync.Plan.self, from: data) {
            plan = cached
        }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        // Ops parked by a previous run that died before applying (#512).
        Task { @MainActor in self.drainDurable() }
    }

    private func adopt(planData data: Data) {
        guard let decoded = try? WatchSync.decode(WatchSync.Plan.self, from: data) else { return }
        Task { @MainActor in
            self.plan = decoded
            UserDefaults.standard.set(data, forKey: Self.planDefaultsKey)
        }
    }

    /// transferUserInfo queues across launches and reachability gaps —
    /// exactly the durability a just-finished routine deserves.
    func send(_ result: WatchSync.SessionResult) {
        guard let data = try? WatchSync.encode(result) else { return }
        WCSession.default.transferUserInfo(["sessionResult": data])
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        if let data = context["plan"] as? Data {
            adopt(planData: data)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext["plan"] as? Data {
            adopt(planData: data)
        }
    }

    // MARK: - Live mirror (#322)

    /// A phone op over the reachable channel — fold it into the wrist's
    /// working copy on the main actor. Not durable, so no A4 concern.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message["liveOp"] as? Data,
              let op = try? WatchSync.decode(LiveSession.Op.self, from: data) else { return }
        Task { @MainActor in self.live.ingest(op) }
    }

    /// A phone op queued while the wrist was unreachable. ⚠️ A4: the
    /// transfer is acked the moment this method RETURNS, so the op must
    /// be DURABLE before then — it parks synchronously, applies on the
    /// main actor, and a relaunch drains whatever a death in between
    /// left behind (the phone side has kept this rule since the A4 bug
    /// hunt; the wrist deferred it until #512).
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["liveOp"] as? Data else { return }
        Self.parkDurable(data)
        Task { @MainActor in self.drainDurable() }
    }

    // MARK: - Durable op parking (A4, #512)

    private static let parkedOpsKey = "pendingPhoneLiveOps"
    private static let parkedCap = 256
    private static let parkLock = NSLock()
    /// The drain's count-based removal is only correct while the park
    /// APPENDS during a drain — a cap eviction mid-drain would shift the
    /// queue and delete a never-applied op (stage-3 review). Guarded by
    /// `parkLock` like everything else here.
    private static var isDraining = false

    private static func parkDurable(_ data: Data) {
        parkLock.lock(); defer { parkLock.unlock() }
        var queue = (UserDefaults.standard.array(forKey: parkedOpsKey) as? [Data]) ?? []
        queue.append(data)
        if !isDraining, queue.count > parkedCap {
            queue.removeFirst(queue.count - parkedCap)
        }
        UserDefaults.standard.set(queue, forKey: parkedOpsKey)
    }

    /// Applies every parked op in arrival order, then clears the park.
    /// Reducer application is idempotent by opId, so a death between
    /// apply and clear only means a harmless replay next time.
    @MainActor
    func drainDurable() {
        Self.parkLock.lock()
        let queue = (UserDefaults.standard.array(forKey: Self.parkedOpsKey) as? [Data]) ?? []
        Self.isDraining = true
        Self.parkLock.unlock()
        defer {
            Self.parkLock.lock()
            Self.isDraining = false
            Self.parkLock.unlock()
        }
        guard !queue.isEmpty else { return }
        for data in queue {
            guard let op = try? WatchSync.decode(LiveSession.Op.self, from: data) else { continue }
            live.ingest(op)
        }
        Self.parkLock.lock()
        var remaining = (UserDefaults.standard.array(forKey: Self.parkedOpsKey) as? [Data]) ?? []
        remaining.removeFirst(min(queue.count, remaining.count))
        UserDefaults.standard.set(remaining, forKey: Self.parkedOpsKey)
        Self.parkLock.unlock()
    }
}
