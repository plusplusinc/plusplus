#if os(iOS) || os(watchOS)
import Foundation
import HealthKit
import OSLog

extension WorkoutMirror {
    /// The link through HealthKit, in the order the link test proved on both devices
    /// (2026-11-27). Made once, at launch on the phone (`listen()`), so a mirrored session the
    /// system hands over is never missed.
    public static let live: Self = {
        let (events, continuation) = AsyncStream.makeStream(of: MirrorEvent.self)
        let link = MirrorLink(relay: MirrorRelay(continuation: continuation))
        #if os(iOS)
        HealthClient.store.workoutSessionMirroringStartHandler = { mirrored in
            Task { await link.adopt(mirrored) }
        }
        #endif
        return Self(
            events: events,
            openWatchApp: {
                #if os(iOS)
                try await HealthClient.store.startWatchApp(toHandle: MirrorLink.configuration)
                #endif
            },
            begin: { try await link.begin() },
            end: { await link.end() },
            recover: { await link.recover() },
            send: { try await link.send($0) },
        )
    }()

    /// Installs the phone's handler for mirrored sessions: called from the app's launch.
    public static func listen() {
        _ = live
    }
}

/// The one workout session the link runs on, and, on the Watch, its builder.
private actor MirrorLink {
    static var configuration: HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        return configuration
    }

    let relay: MirrorRelay
    var session: HKWorkoutSession?
    #if os(watchOS)
    var builder: HKLiveWorkoutBuilder?
    #endif

    init(relay: MirrorRelay) {
        self.relay = relay
    }

    /// Phone: a mirrored session handed over, in place of the last.
    func adopt(_ mirrored: HKWorkoutSession) {
        mirrored.delegate = relay
        session = mirrored
        relay.continuation.yield(.connected)
    }

    func send(_ data: Data) async throws {
        guard let session else { throw MirrorError.noSession }
        try await session.sendToRemoteWorkoutSession(data: data)
    }

    #if os(watchOS)
    func begin() async throws {
        if let session, session.state != .ended {
            session.end()
        }
        let configuration = Self.configuration
        let store = HealthClient.store
        let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: store,
            workoutConfiguration: configuration,
        )
        session.delegate = relay
        self.session = session
        self.builder = builder
        session.prepare()
        let start = Date()
        await mirror()
        session.startActivity(with: start)
        try await builder.beginCollection(at: start)
    }

    func end() async {
        guard let session else { return }
        session.end()
        self.session = nil
        guard let builder else { return }
        self.builder = nil
        do {
            try await builder.endCollection(at: .now)
        } catch {
            Logger.mirror.error("End collection failed: \(error)")
        }
        builder.discardWorkout()
    }

    func recover() async -> Bool {
        let recovered: HKWorkoutSession? = await withCheckedContinuation { continuation in
            HealthClient.store.recoverActiveWorkoutSession { session, _ in
                continuation.resume(returning: session)
            }
        }
        guard let recovered else { return false }
        recovered.delegate = relay
        session = recovered
        builder = recovered.associatedWorkoutBuilder()
        await mirror()
        return true
    }

    private func mirror() async {
        do {
            try await session?.startMirroringToCompanionDevice()
            relay.continuation.yield(.connected)
        } catch {
            Logger.mirror.error("Mirroring did not start: \(error)")
            relay.continuation.yield(.disconnected)
        }
    }
    #else
    func begin() async throws {
        throw MirrorError.unavailable
    }

    func end() async {
        session = nil
    }

    func recover() async -> Bool {
        false
    }
    #endif
}

/// HealthKit's delegate calls, copied into the link's events.
private final class MirrorRelay: NSObject, HKWorkoutSessionDelegate, Sendable {
    let continuation: AsyncStream<MirrorEvent>.Continuation

    init(continuation: AsyncStream<MirrorEvent>.Continuation) {
        self.continuation = continuation
    }

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date,
    ) {
        if toState == .ended {
            continuation.yield(.ended)
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        Logger.mirror.error("Workout session failed: \(error)")
    }

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didDisconnectFromRemoteDeviceWithError error: (any Error)?,
    ) {
        continuation.yield(.disconnected)
    }

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didReceiveDataFromRemoteWorkoutSession data: [Data],
    ) {
        for item in data {
            continuation.yield(.received(item))
        }
    }
}

extension Logger {
    static let mirror = Logger(subsystem: "com.plusplusinc.plusplus", category: "mirror")
}
#endif
