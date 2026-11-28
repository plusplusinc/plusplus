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
    @ObservationIgnored private var isAsking = false
    /// The workout sessions deleted from Log whose Health workout is owed a removal, the oldest
    /// first, kept in `defaults` as their uuids so a relaunch still makes them. None is ever
    /// dropped unmade: a dropped one would leave its workout in Health for good.
    @ObservationIgnored private(set) var removalsOwed: [WorkoutSession.ID]
    /// The removals owed since the last `removalsToSettle()`, listed already or not: their
    /// delete may land after that read's settle looks, so it never drops them. In memory only,
    /// as nothing is mid-settle across a relaunch.
    @ObservationIgnored private var owedSinceRead: Set<WorkoutSession.ID> = []
    @ObservationIgnored private let defaults: UserDefaults

    /// Where the prompt on Log that asks to sync to Apple Health stands on this device: nil
    /// until the first finish since the prompt came to the app, whatever Health's access was
    /// then. Kept on the device, not in the store, as Health's answer is the device's: a
    /// dismissal synced to another device would hide the prompt where Apple's sheet was never
    /// shown.
    private(set) var offer: Offer?

    enum Offer: String {
        /// A workout was finished since the prompt came to the app, and it wasn't dismissed,
        /// whatever Health's access was then. It shows whenever Health reads as never asked
        /// (`isOffered`): not while it is answered, but again if the answer is undone, as by
        /// resetting the phone's privacy settings.
        case offered
        /// Dismissed with its ×: the prompt never shows again, and Apple's sheet is left
        /// unspent.
        case declined
    }

    /// The note that takes the prompt's place on Log for a moment, saying where syncing can be
    /// turned on later; nil while none shows. In memory only: after a relaunch it is gone.
    public private(set) var note: Note?

    public enum Note: Equatable, Sendable {
        /// The prompt was dismissed: Settings can still turn syncing on.
        case dismissed
        /// Apple's sheet was answered Don't Allow: only the Health app can turn it on.
        case denied
    }

    /// The key the removals owed are kept under, for a reset.
    public static let removalsKey = "healthRemovalsOwed"
    /// The key Log's prompt's offer is kept under.
    static let offerKey = "healthOffer"
    /// Every key this keeps on the device, for a reset.
    public static let keys = [removalsKey, offerKey]

    public init(client: HealthClient, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
        removalsOwed = (defaults.stringArray(forKey: Self.removalsKey) ?? [])
            .compactMap(UUID.init(uuidString:))
        offer = defaults.string(forKey: Self.offerKey).flatMap(Offer.init(rawValue:))
    }

    /// Whether Log's prompt to sync to Apple Health is offered: a finish has made the offer, its
    /// × hasn't dismissed it, and the system reads Health as never asked. While Apple's sheet
    /// is answered, from the prompt or Settings, or with Health unavailable, it is
    /// not, with nothing more stored: it is the access read that takes it back. Log shows it
    /// only while it holds a finished workout (`AppSession.healthPrompt`).
    var isOffered: Bool {
        offer == .offered && access == .notAsked
    }

    /// Makes the prompt's offer at a finish, the first since the app kept one, whatever the access
    /// then. Whether it shows is the access's to say (`isOffered`): not while Health is
    /// answered or not on the device.
    func offerAtFinish() {
        guard offer == nil else { return }
        keepOffer(.offered)
    }

    /// The prompt's ×: it goes for good, its note in its place; Settings' row still asks.
    public func declineOffer() {
        keepOffer(.declined)
        note = .dismissed
    }

    /// Shows the note for a Don't Allow answered from the prompt.
    func noteDenied() {
        note = .denied
    }

    /// The note's OK, its fill run out, or Log left: it goes.
    public func endNote() {
        note = nil
    }

    private func keepOffer(_ offer: Offer) {
        self.offer = offer
        defaults.set(offer.rawValue, forKey: Self.offerKey)
    }

    /// Reads the access, as Settings opens or after a trip to the system's settings.
    public func refresh() {
        readsBegun += 1
        keepAccess(client.access())
    }

    /// Reads the access off the main actor, as a catch-up does, so HealthKit's answer never
    /// holds up a frame. An answer overtaken by a later read, as after the person allowed
    /// saving, is dropped: it would show saving off with saving on.
    func refreshed() async {
        readsBegun += 1
        let read = readsBegun
        let answer = await Self.read(client)
        guard read == readsBegun else { return }
        keepAccess(answer)
    }

    /// Written only when the answer changes: Log and Settings read the access in their bodies,
    /// and a write of the same answer at each catch-up would redraw them.
    private func keepAccess(_ answer: HealthAccess) {
        guard answer != access else { return }
        access = answer
    }

    @concurrent
    private nonisolated static func read(_ client: HealthClient) async -> HealthAccess {
        client.access()
    }

    /// Brings up Apple's sheet, then reads what was answered. The session's ask is the only one
    /// (`AppSession.askToSaveToHealth()`), so an answer is always followed by a catch-up. One at
    /// a time: an ask while one is out, as from a double tap, does nothing and returns false.
    @discardableResult
    func ask() async -> Bool {
        guard !isAsking else { return false }
        isAsking = true
        defer { isAsking = false }
        do {
            try await client.ask()
        } catch {
            Logger.session.error("Apple Health's ask didn't come up: \(error)")
        }
        refresh()
        return true
    }

    /// Removes every workout the app saved for the workout sessions `ids` (`HealthClient.remove`).
    func remove(_ ids: [WorkoutSession.ID]) async throws {
        try await client.remove(ids)
    }

    /// Whether a removal is owed for the workout session `id`: deleted from Log, so never saved.
    func owesRemoval(of id: WorkoutSession.ID) -> Bool {
        removalsOwed.contains(id)
    }

    /// Keeps a removal owed for the workout session `id`, on the device, before its delete is
    /// sent; none while Health was never asked or isn't on the device, as nothing of it can be
    /// there. With the access not yet read, one is kept.
    func oweRemoval(of id: WorkoutSession.ID) {
        guard access != .notAsked, access != .unavailable else { return }
        owedSinceRead.insert(id)
        guard !owesRemoval(of: id) else { return }
        keepRemovals(removalsOwed + [id])
    }

    /// The removals owed now, for a catch-up to settle once every delete sent so far has
    /// landed (`settle(_:held:)`).
    func removalsToSettle() -> [WorkoutSession.ID] {
        owedSinceRead = []
        return removalsOwed
    }

    /// Of `removals`, from `removalsToSettle()`, drops those whose workout the store still
    /// `held`, as their delete never landed, unless owed again since the read: that delete is
    /// still to land, and the catch-up it asked for settles it. Returns those whose delete
    /// landed, to make.
    func settle(
        _ removals: [WorkoutSession.ID],
        held: Set<WorkoutSession.ID>,
    ) -> [WorkoutSession.ID] {
        forgetRemovals(of: held.subtracting(owedSinceRead))
        return removals.filter { !held.contains($0) }
    }

    /// Drops the removals owed for `ids` without making them.
    func forgetRemovals(of ids: Set<WorkoutSession.ID>) {
        keepRemovals(removalsOwed.filter { !ids.contains($0) })
    }

    /// Removes from Health, in one call, the workouts saved for `ids`, then stops owing them.
    /// Throws, owing them still, when Health refuses.
    func makeRemovals(_ ids: [WorkoutSession.ID]) async throws {
        try await client.remove(ids)
        forgetRemovals(of: Set(ids))
    }

    /// Written only when the list changes.
    private func keepRemovals(_ owed: [WorkoutSession.ID]) {
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
