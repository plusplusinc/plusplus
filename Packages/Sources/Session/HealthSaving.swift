import Health
import Observation
import OSLog
import WorkoutStore

/// Saving finished workouts to Apple Health: whether the system lets the app, which Settings
/// shows, the ask, and each save. A save that fails is logged and shows nothing: there is
/// nothing the person can do about it.
@Observable
public final class HealthSaving {
    /// As of the last `refresh()`.
    public private(set) var access: HealthAccess
    @ObservationIgnored private let client: HealthClient

    public init(client: HealthClient) {
        self.client = client
        access = client.access()
    }

    /// Reads the access again, as after a trip to the system's settings.
    public func refresh() {
        access = client.access()
    }

    /// Brings up Apple's sheet, then reads what was answered.
    public func ask() async {
        do {
            try await client.ask()
        } catch {
            Logger.session.error("Apple Health's ask didn't come up: \(error)")
        }
        refresh()
    }

    /// Saves `workout` to Health, if the system lets the app now.
    func save(_ workout: HealthWorkout) async {
        refresh()
        guard access == .on else { return }
        do {
            _ = try await client.save(workout)
        } catch {
            Logger.session.error("A workout didn't save to Apple Health: \(error)")
        }
    }
}
