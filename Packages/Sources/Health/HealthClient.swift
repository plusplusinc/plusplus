import Foundation
import WorkoutStore

/// Whether the app may save workouts to Apple Health, as the system answers it.
public enum HealthAccess: Equatable, Sendable {
    /// Health isn't on this device, or isn't allowed on it.
    case unavailable
    /// Never asked: Apple's sheet hasn't been shown.
    case notAsked
    case on
    case off
}

/// The app's one way to Apple Health: closures, so everything above it is tested with a fake
/// that records what it was asked, and only `live` calls HealthKit.
public struct HealthClient: Sendable {
    /// The access the system gives now; synchronous, as HealthKit answers it.
    public var access: @Sendable () -> HealthAccess
    /// Brings up Apple's sheet, asking only to write workouts; returns at once if answered before.
    public var ask: @Sendable () async throws -> Void
    /// Removes every workout the app saved for any of the workout sessions, by the tag each
    /// carries; succeeds when none is there.
    public var remove: @Sendable ([WorkoutSession.ID]) async throws -> Void
    /// Saves one workout, tagged with its workout session's id, and returns Health's id for it;
    /// nil when Health saved it but didn't hand it back, as with the phone locked. A save adds:
    /// to replace what an earlier save left, `remove` its workout session first. Callers make one
    /// remove-then-save at a time per workout session, since the replace is not safe against
    /// itself: two run side by side can both remove before either saves, and leave two.
    public var save: @Sendable (HealthWorkout) async throws -> UUID?

    public init(
        access: @escaping @Sendable () -> HealthAccess,
        ask: @escaping @Sendable () async throws -> Void,
        remove: @escaping @Sendable ([WorkoutSession.ID]) async throws -> Void,
        save: @escaping @Sendable (HealthWorkout) async throws -> UUID?,
    ) {
        self.access = access
        self.ask = ask
        self.remove = remove
        self.save = save
    }

    /// No Health: nothing asked, removed, or saved.
    public static let unavailable = Self(
        access: { .unavailable },
        ask: { },
        remove: { _ in },
        save: { _ in nil },
    )
}
