import Foundation
import Health
import Observation
import OSLog
import WorkoutStore

/// Saving finished workouts to Apple Health: whether the system lets the app, which Settings
/// shows, and the ask, removals, and saves the session makes (`AppSession.askToSaveToHealth()`,
/// `AppSession.catchUpHealth()`). Nothing here reads HealthKit until it is first used, so none
/// of it runs on the way to the app's first frame.
@Observable
public final class HealthSaving {
    /// As of the last read; nil until the first.
    public private(set) var access: HealthAccess?
    @ObservationIgnored private let client: HealthClient

    public init(client: HealthClient) {
        self.client = client
    }

    /// Reads the access, as Settings opens or after a trip to the system's settings.
    public func refresh() {
        access = client.access()
    }

    /// Reads the access off the main actor, as a catch-up does, so HealthKit's answer never
    /// holds up a frame.
    func refreshed() async {
        access = await Self.read(client)
    }

    @concurrent
    private nonisolated static func read(_ client: HealthClient) async -> HealthAccess {
        client.access()
    }

    /// Brings up Apple's sheet, then reads what was answered. The session's ask is the only one
    /// (`AppSession.askToSaveToHealth()`), so an answer is always followed by a catch-up.
    func ask() async {
        do {
            try await client.ask()
        } catch {
            Logger.session.error("Apple Health's ask didn't come up: \(error)")
        }
        refresh()
    }

    /// Removes every workout the app saved for the logged workouts `ids` (`HealthClient.remove`).
    func remove(_ ids: [LoggedWorkout.ID]) async throws {
        try await client.remove(ids)
    }

    /// Saves `workout` to Health, returning Health's id for it, or nil when Health saved it and
    /// handed none back (`HealthClient.save`). Throws when it didn't save, as when the system no
    /// longer lets the app.
    func save(_ workout: HealthWorkout) async throws -> UUID? {
        try await client.save(workout)
    }
}
