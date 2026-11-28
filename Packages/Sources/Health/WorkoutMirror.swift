import Foundation

/// What the link between the phone and the Watch reports.
public enum MirrorEvent: Equatable, Sendable {
    /// A mirrored session is up: on the phone, one handed over; on the Watch, mirroring began.
    case connected
    case received(Data)
    /// The other device went out of reach; the system reconnects by itself.
    case disconnected
    /// The workout session ended.
    case ended
}

/// The phone and the Watch's link: Apple's mirrored workout session (`HKWorkoutSession`), as
/// closures, so everything above it is tested with a fake and only `live` calls HealthKit. One
/// stream of events for the app's life; the phone and the Watch each use their half.
public struct WorkoutMirror: Sendable {
    public var events: AsyncStream<MirrorEvent>
    /// Phone: brings up the Watch app to start a workout session that mirrors here. Throws
    /// with no Watch, or none in reach.
    public var openWatchApp: @Sendable () async throws -> Void
    /// Watch: starts a strength workout session and its mirroring to the phone.
    public var begin: @Sendable () async throws -> Void
    /// Watch: ends the workout session and discards what it collected: the phone saves the
    /// workout to Apple Health from its own times.
    public var end: @Sendable () async -> Void
    /// Watch: takes back a workout session the system kept through a relaunch, and mirrors it
    /// again; false with none.
    public var recover: @Sendable () async -> Bool
    /// Sends to the other device; throws at once when the link is down.
    public var send: @Sendable (Data) async throws -> Void

    public init(
        events: AsyncStream<MirrorEvent>,
        openWatchApp: @escaping @Sendable () async throws -> Void = { },
        begin: @escaping @Sendable () async throws -> Void = { },
        end: @escaping @Sendable () async -> Void = { },
        recover: @escaping @Sendable () async -> Bool = { false },
        send: @escaping @Sendable (Data) async throws -> Void,
    ) {
        self.events = events
        self.openWatchApp = openWatchApp
        self.begin = begin
        self.end = end
        self.recover = recover
        self.send = send
    }

    /// No Watch: nothing opens, nothing arrives, and a send fails.
    public static var unavailable: Self {
        Self(
            events: AsyncStream { $0.finish() },
            openWatchApp: { throw MirrorError.unavailable },
            begin: { throw MirrorError.unavailable },
            send: { _ in throw MirrorError.unavailable },
        )
    }
}

public enum MirrorError: Error, Sendable {
    case unavailable
    case noSession
}
