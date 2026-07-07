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
}
