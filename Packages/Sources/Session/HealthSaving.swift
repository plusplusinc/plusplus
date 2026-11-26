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
    /// Counts the reads begun, so a read that comes back after a later one began is dropped.
    @ObservationIgnored private var readsBegun = 0
    /// The Health workouts owed a removal, for logged workouts deleted from Log, the oldest
    /// first, kept in `defaults` so a relaunch still makes them.
    @ObservationIgnored private(set) var removalsOwed: [OwedRemoval]
    @ObservationIgnored private let defaults: UserDefaults?

    /// A logged workout deleted from Log, and Health's id for it when the log had one.
    struct OwedRemoval: Codable, Equatable {
        let id: LoggedWorkout.ID
        let healthID: UUID?
    }

    /// The most removals kept owed: past it the oldest is dropped, so the list stays small while
    /// saving is off for good. One removal call makes them all, so their number costs nothing more.
    static let removalsKept = 100
    static let removalsKey = "healthRemovalsOwed"

    /// With `defaults`, the removals owed outlive the session; with none, as in previews and
    /// the UI tests' fake, they are kept only in memory.
    public init(client: HealthClient, defaults: UserDefaults? = nil) {
        self.client = client
        self.defaults = defaults
        removalsOwed = defaults?.data(forKey: Self.removalsKey)
            .flatMap { try? JSONDecoder().decode([OwedRemoval].self, from: $0) } ?? []
    }

    /// Reads the access, as Settings opens or after a trip to the system's settings.
    public func refresh() {
        readsBegun += 1
        access = client.access()
    }

    /// Reads the access off the main actor, as a catch-up does, so HealthKit's answer never
    /// holds up a frame. An answer overtaken by a later read, as after the person allowed
    /// saving, is dropped: it would show saving off with saving on.
    func refreshed() async {
        readsBegun += 1
        let read = readsBegun
        let answer = await Self.read(client)
        guard read == readsBegun else { return }
        access = answer
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
        try await client.remove(ids, [])
    }

    /// Whether a removal is owed for the logged workout `id`: deleted from Log, so never saved.
    func owesRemoval(of id: LoggedWorkout.ID) -> Bool {
        removalsOwed.contains { $0.id == id }
    }

    /// Keeps a removal owed for the logged workout `id`, on the device, before its delete is sent.
    func oweRemoval(of id: LoggedWorkout.ID, healthID: UUID?) {
        guard !owesRemoval(of: id) else { return }
        keepRemovals((removalsOwed + [OwedRemoval(id: id, healthID: healthID)])
            .suffix(Self.removalsKept))
    }

    /// Drops the removals owed for `ids` without making them: their delete never landed.
    func forgetRemovals(of ids: Set<LoggedWorkout.ID>) {
        keepRemovals(removalsOwed.filter { !ids.contains($0.id) })
    }

    /// Removes from Health, in one call, the workouts owed for `owed`, then stops owing them.
    /// Throws, owing them still, when Health refuses.
    func makeRemovals(_ owed: [OwedRemoval]) async throws {
        try await client.remove(owed.map(\.id), owed.compactMap(\.healthID))
        forgetRemovals(of: Set(owed.map(\.id)))
    }

    private func keepRemovals(_ owed: some Collection<OwedRemoval>) {
        removalsOwed = Array(owed)
        guard let defaults else { return }
        if removalsOwed.isEmpty {
            defaults.removeObject(forKey: Self.removalsKey)
        } else if let data = try? JSONEncoder().encode(removalsOwed) {
            defaults.set(data, forKey: Self.removalsKey)
        }
    }

    /// Saves `workout` to Health, returning Health's id for it, or nil when Health saved it and
    /// handed none back (`HealthClient.save`). Throws when it didn't save, as when the system no
    /// longer lets the app.
    func save(_ workout: HealthWorkout) async throws -> UUID? {
        try await client.save(workout)
    }
}
