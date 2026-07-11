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
    /// working copy on the main actor.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        ingestLiveOp(message["liveOp"])
    }

    /// A phone op queued while the wrist was unreachable, or the plan.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        ingestLiveOp(userInfo["liveOp"])
    }

    private func ingestLiveOp(_ value: Any?) {
        guard let data = value as? Data,
              let op = try? WatchSync.decode(LiveSession.Op.self, from: data) else { return }
        Task { @MainActor in self.live.ingest(op) }
    }
}
