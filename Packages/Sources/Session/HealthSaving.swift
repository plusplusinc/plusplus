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
    /// The logged workouts deleted from Log whose Health workout is owed a removal, the oldest
    /// first, kept in `defaults` as their uuids so a relaunch still makes them. None is ever
    /// dropped unmade: a dropped one would leave its workout in Health for good.
    @ObservationIgnored private(set) var removalsOwed: [LoggedWorkout.ID]
    /// The removals owed since the last `removalsToSettle()`, listed already or not: their
    /// delete may land after that read's settle looks, so it never drops them. In memory only,
    /// as nothing is mid-settle across a relaunch.
    @ObservationIgnored private var owedSinceRead: Set<LoggedWorkout.ID> = []
    @ObservationIgnored private let defaults: UserDefaults

    /// Where the card on Log that asks to save to Apple Health stands on this device: nil until
    /// the first finish that finds Health not asked, or not read yet. Kept on the device, not in
    /// the store, as Health's answer is the device's: a "Not now" synced to another device would
    /// hide the card where Apple's sheet was never shown.
    private(set) var offer: Offer?

    enum Offer: String {
        /// A finish made the offer; the card shows while Health is still not asked.
        case offered
        /// "Not now": the card never shows again, and Apple's sheet is left unspent.
        case declined
    }

    /// The key the removals owed are kept under, for a reset.
    public static let removalsKey = "healthRemovalsOwed"
    /// The key the card's offer is kept under, for a reset.
    public static let offerKey = "healthOffer"
    /// Every key this keeps on the device, for a reset.
    public static let keys = [removalsKey, offerKey]

    public init(client: HealthClient, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
        removalsOwed = (defaults.stringArray(forKey: Self.removalsKey) ?? [])
            .compactMap(UUID.init(uuidString:))
        offer = defaults.string(forKey: Self.offerKey).flatMap(Offer.init(rawValue:))
    }

    /// Whether Log shows the card that asks to save to Apple Health: a finish has made the
    /// offer, "Not now" hasn't turned it down, and the system reads Health as never asked. Once
    /// Apple's sheet is answered, from the card or Settings, or with Health unavailable, it is
    /// gone with nothing more stored.
    public var showsOffer: Bool {
        offer == .offered && access == .notAsked
    }

    /// Makes the card's offer at a finish, the first since the app kept one, unless the access
    /// last read says Health was asked or isn't here. Whether it shows waits on the access.
    func offerAtFinish() {
        guard offer == nil, access == nil || access == .notAsked else { return }
        keepOffer(.offered)
    }

    /// "Not now" on the card: it goes for good; Settings' row still asks.
    public func declineOffer() {
        keepOffer(.declined)
    }

    private func keepOffer(_ offer: Offer) {
        self.offer = offer
        defaults.set(offer.rawValue, forKey: Self.offerKey)
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
        try await client.remove(ids)
    }

    /// Whether a removal is owed for the logged workout `id`: deleted from Log, so never saved.
    func owesRemoval(of id: LoggedWorkout.ID) -> Bool {
        removalsOwed.contains(id)
    }

    /// Keeps a removal owed for the logged workout `id`, on the device, before its delete is
    /// sent; none while Health was never asked or isn't on the device, as nothing of it can be
    /// there. With the access not yet read, one is kept.
    func oweRemoval(of id: LoggedWorkout.ID) {
        guard access != .notAsked, access != .unavailable else { return }
        owedSinceRead.insert(id)
        guard !owesRemoval(of: id) else { return }
        keepRemovals(removalsOwed + [id])
    }

    /// The removals owed now, for a catch-up to settle once every delete sent so far has
    /// landed (`settle(_:held:)`).
    func removalsToSettle() -> [LoggedWorkout.ID] {
        owedSinceRead = []
        return removalsOwed
    }

    /// Of `removals`, from `removalsToSettle()`, drops those whose workout the store still
    /// `held`, as their delete never landed, unless owed again since the read: that delete is
    /// still to land, and the catch-up it asked for settles it. Returns those whose delete
    /// landed, to make.
    func settle(_ removals: [LoggedWorkout.ID], held: Set<LoggedWorkout.ID>) -> [LoggedWorkout.ID] {
        forgetRemovals(of: held.subtracting(owedSinceRead))
        return removals.filter { !held.contains($0) }
    }

    /// Drops the removals owed for `ids` without making them.
    func forgetRemovals(of ids: Set<LoggedWorkout.ID>) {
        keepRemovals(removalsOwed.filter { !ids.contains($0) })
    }

    /// Removes from Health, in one call, the workouts saved for `ids`, then stops owing them.
    /// Throws, owing them still, when Health refuses.
    func makeRemovals(_ ids: [LoggedWorkout.ID]) async throws {
        try await client.remove(ids)
        forgetRemovals(of: Set(ids))
    }

    /// Written only when the list changes.
    private func keepRemovals(_ owed: [LoggedWorkout.ID]) {
        guard owed != removalsOwed else { return }
        removalsOwed = owed
        if owed.isEmpty {
            defaults.removeObject(forKey: Self.removalsKey)
        } else {
            defaults.set(owed.map(\.uuidString), forKey: Self.removalsKey)
        }
    }

    /// Saves `workout` to Health, returning Health's id for it, or nil when Health saved it and
    /// handed none back (`HealthClient.save`). Throws when it didn't save, as when the system no
    /// longer lets the app.
    func save(_ workout: HealthWorkout) async throws -> UUID? {
        try await client.save(workout)
    }
}
