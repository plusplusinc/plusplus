import Foundation
import Health
import Observation
import OSLog
import WorkoutStore

/// The phone's side of the link to the Watch: Start brings up the Watch app, and once the
/// system hands over its mirrored session, every change to the workout goes to the Watch as the
/// workout stands, and the Watch's actions come back to `AppSession.receive(_:at:)`. With no
/// Watch, Start's call fails, nothing is handed over, and the phone runs as it did without one.
public final class PhoneLink {
    private weak var session: AppSession?
    private let mirror: WorkoutMirror
    private let now: () -> Date
    /// The workout session the Watch was brought up for, so it is brought up once.
    private var opened: UUID?
    /// The workout session running, as last seen: its end is sent once it goes.
    private var running: WorkoutSession?
    /// Whether a mirrored session is up.
    private var isConnected = false
    /// Whether the Watch has answered on the mirrored session since it was handed over.
    private var isAnswered = false
    /// Rises with every state sent; the Watch keeps only the highest.
    private var rev = 0
    /// The highest Watch action applied, by workout session.
    private var applied: [UUID: Int] = [:]
    /// Whether the next state carries the plan: after a (re)connect, and after an edit.
    private var sendsPlan = true
    private var planSent: Workout?
    private var pendingState: Task<Void, Never>?
    private var hello: Task<Void, Never>?
    private var listening: Task<Void, Never>?

    /// The least time between two states, so a burst of taps sends the newest only.
    static let stateSpacing = 0.15

    public init(session: AppSession, mirror: WorkoutMirror, now: @escaping () -> Date = { .now }) {
        self.session = session
        self.mirror = mirror
        self.now = now
        running = session.workoutSession
        session.onWorkoutChange = { [weak self] in self?.workoutChanged() }
        let events = mirror.events
        listening = Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
    }

    // MARK: The phone's changes

    private func workoutChanged() {
        guard let session else { return }
        let current = session.workoutSession
        if let running, current?.id != running.id {
            let ended = session.log?.workoutSessions.last { $0.id == running.id }
            sendEnd(LinkEnd(ended, at: now()), for: running.id)
        }
        running = current
        guard let current else { return }
        if opened != current.id, current.sets.isEmpty {
            opened = current.id
            applied[current.id] = 0
            let mirror = mirror
            Task {
                do {
                    try await mirror.openWatchApp()
                } catch {
                    Logger.link.info("The Watch app did not open: \(error)")
                }
            }
        }
        if planSent != session.current {
            sendsPlan = true
        }
        sendStateSoon()
    }

    // MARK: The link

    private func handle(_ event: MirrorEvent) {
        switch event {
        case .connected:
            isConnected = true
            isAnswered = false
            sendsPlan = true
            sayHello()
        case let .received(data):
            isAnswered = true
            hello?.cancel()
            receive(data)
        case .disconnected:
            isConnected = false
        case .ended:
            isConnected = false
            hello?.cancel()
        }
    }

    /// Hello once a second until the Watch answers: a send in the instant of the hand-over is
    /// lost (the link test, 2026-11-27).
    private func sayHello() {
        hello?.cancel()
        hello = Task { [weak self] in
            for _ in 0 ..< 30 {
                guard let self, !self.isAnswered, !Task.isCancelled else { return }
                if let id = running?.id {
                    send(.hello, session: id)
                } else {
                    send(.ended(LinkEnd(nil, at: now())), session: UUID())
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func receive(_ data: Data) {
        guard let message = LinkMessage.decoded(from: data) else {
            Logger.link.error("A message from the Watch did not read")
            return
        }
        guard let running, message.session == running.id else {
            send(.ended(LinkEnd(nil, at: now())), session: message.session)
            return
        }
        switch message.body {
        case .hello:
            sendsPlan = true
            sendStateSoon()
        case let .actions(actions):
            var highest = applied[running.id] ?? 0
            for action in actions.sorted(by: { $0.seq < $1.seq }) where action.seq > highest {
                highest = action.seq
                applied[running.id] = highest
                if let wanted = action.action.action {
                    session?.receive(wanted, at: action.at)
                }
            }
            sendStateSoon()
        case .state, .ended:
            break
        }
    }

    /// The newest state, at most one each `stateSpacing`.
    private func sendStateSoon() {
        guard pendingState == nil else { return }
        pendingState = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.stateSpacing))
            self?.pendingState = nil
            self?.sendState()
        }
    }

    private func sendState() {
        guard isConnected, let session, let running = session.workoutSession else { return }
        rev += 1
        let plan = sendsPlan ? session.current : nil
        let state = LinkState(
            rev: rev,
            watchSeq: applied[running.id] ?? 0,
            plan: plan,
            session: running,
        )
        if plan != nil {
            planSent = plan
            sendsPlan = false
        }
        send(.state(state), session: running.id)
    }

    /// The workout ended: three tries a second apart, as the Watch may be a moment away.
    private func sendEnd(_ end: LinkEnd, for id: UUID) {
        guard isConnected else { return }
        Task { [weak self] in
            for _ in 0 ..< 3 {
                self?.send(.ended(end), session: id)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func send(_ body: LinkMessage.Body, session id: UUID) {
        guard let data = try? LinkMessage(session: id, body: body).encoded() else { return }
        let mirror = mirror
        Task {
            do {
                try await mirror.send(data)
            } catch {
                Logger.link.info("A send to the Watch failed: \(error)")
            }
        }
    }
}

extension Logger {
    static let link = Logger(subsystem: "com.plusplusinc.plusplus", category: "link")
}
