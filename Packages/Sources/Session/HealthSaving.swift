import Health
import Observation
import OSLog
import WorkoutStore

/// Saving finished workouts to Apple Health: whether the system lets the app, which Settings
/// shows, the ask, and each save. A save that fails is logged and shows nothing: there is
/// nothing the person can do about it. Nothing here reads HealthKit until it is first used, so
/// none of it runs on the way to the app's first frame.
@Observable
public final class HealthSaving {
    /// As of the last `refresh()`; nil until the first.
    public private(set) var access: HealthAccess?
    @ObservationIgnored private let client: HealthClient

    public init(client: HealthClient) {
        self.client = client
    }

    /// Reads the access, as Settings opens or after a trip to the system's settings.
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

    /// Saves `workout` to Health, if the system lets the app now; with saving on, a workout
    /// withheld is logged for why.
    func save(_ workout: Result<HealthWorkout, HealthWorkout.Withheld>) async {
        refresh()
        guard access == .on else { return }
        switch workout {
        case let .success(workout):
            do {
                try await client.save(workout)
            } catch {
                Logger.session.error("A workout didn't save to Apple Health: \(error)")
            }
        case .failure(.resumedBefore):
            Logger.session.notice("Not saved to Apple Health: its pauses' times aren't kept")
        case .failure(.notFinished):
            Logger.session.notice("Not saved to Apple Health: it hasn't ended")
        }
    }
}
