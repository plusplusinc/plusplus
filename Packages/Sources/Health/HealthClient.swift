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
    /// Saves one workout in place of any the app saved for the same logged workout, so a save
    /// repeated leaves one, and returns Health's id for it; nil when Health saved it but didn't
    /// hand it back, as with the phone locked.
    public var save: @Sendable (HealthWorkout) async throws -> UUID?

    public init(
        access: @escaping @Sendable () -> HealthAccess,
        ask: @escaping @Sendable () async throws -> Void,
        save: @escaping @Sendable (HealthWorkout) async throws -> UUID?,
    ) {
        self.access = access
        self.ask = ask
        self.save = save
    }

    /// No Health: nothing asked, nothing saved.
    public static let unavailable = Self(
        access: { .unavailable },
        ask: { },
        save: { _ in nil },
    )
}
