import Foundation
import Health
import Observation
import OSLog
import WorkoutStore

/// What the Watch plays on the wrist, named by what happened; the Watch app picks each one's
/// feel.
public enum WatchHaptic: Equatable, Sendable {
    case setLogged
    case restEnded
    case startInEnded
    case setRanOut
    case finished
}

/// The workout on the Watch: its copy of the phone's workout and the wrist's taps on it
/// (`LinkedWorkout`), what time does to it, and the link to the phone. Everything the Watch
/// changes is an action (`WorkoutAction`), so the phone hears each one.
@Observable
public final class WatchWorkout {
    /// The workout, once the phone's first state has come, or the demo's.
    public private(set) var linked: LinkedWorkout?
    /// Whether the phone answered the last thing sent.
    public private(set) var isPhoneInReach = true
    /// The last workout's end, for the finished page, until Done.
    public private(set) var ended: LinkEnd?

    private let mirror: WorkoutMirror
    private let haptic: @MainActor (WatchHaptic) -> Void
    private let write: @MainActor (Data?) -> Void
    private let now: () -> Date
    /// Runs alone, with no phone: the demo.
    private var isAlone = false
    private var clock: Task<Void, Never>?
    private var listening: Task<Void, Never>?
    private var retrying: Task<Void, Never>?
    /// The set a count is due on, and when it came up: the Watch waits `countGrace` for the
    /// phone's own count before beginning one.
    private var dueSince: (set: PlannedSet, at: Date)?

    /// How long the Watch waits for the phone to begin a set's "Start in", which it does as its
    /// screen lands on the set, before beginning it itself.
    public static let countGrace = 2.0
    /// How long the Watch waits for the phone's first state after Start before giving up.
    public static let startWait = 30.0

    public init(
        mirror: WorkoutMirror,
        saved: Data?,
        write: @escaping @MainActor (Data?) -> Void,
        haptic: @escaping @MainActor (WatchHaptic) -> Void,
        now: @escaping () -> Date = { .now },
    ) {
        self.mirror = mirror
        self.write = write
        self.haptic = haptic
        self.now = now
        linked = saved.flatMap { try? JSONDecoder().decode(LinkedWorkout.self, from: $0) }
        if linked?.live == nil {
            linked = nil
        }
    }

    /// The workout as the wrist shows it now.
    public var live: LiveWorkout? {
        linked?.live
    }

    // MARK: Starting and ending

    /// Listens to the phone: from launch, for the app's life.
    public func listen() {
        guard listening == nil else { return }
        let events = mirror.events
        listening = Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
    }

    /// The phone started a workout and brought the app up for it: begins the workout session
    /// that mirrors to the phone, and waits for the phone's first state.
    public func start() async {
        ended = nil
        isAlone = false
        do {
            try await mirror.begin()
        } catch {
            Logger.watch.error("The workout session did not begin: \(error)")
            return
        }
        try? await Task.sleep(for: .seconds(Self.startWait))
        if linked == nil {
            Logger.watch.error("No word from the phone after Start; ending")
            await mirror.end()
        }
    }

    /// At launch: a workout session the system kept through a relaunch is taken back with the
    /// workout saved, or ended with none.
    public func recover() async {
        guard await mirror.recover() else { return }
        if linked == nil {
            await mirror.end()
        } else {
            sendHeld()
            reschedule()
        }
    }

    /// Runs `workout` on the wrist alone, from Start, with no phone.
    public func runAlone(_ workout: Workout) {
        isAlone = true
        ended = nil
        linked = LinkedWorkout(alone: workout, startedAt: now())
        changed()
    }

    /// The finished page's Done: back to idle.
    public func dismissEnded() {
        ended = nil
    }

    // MARK: Taps

    /// The wrist did `action`: shown at once, kept, and sent to the phone.
    public func tap(_ action: WorkoutAction) {
        guard var linked, let before = linked.live else { return }
        let date = now()
        linked.act(action, at: date)
        self.linked = linked
        if case .log = action {
            haptic(.setLogged)
        }
        if action == .finish || action == .discard {
            finishOnWrist(before, action: action, at: date)
        }
        changed()
    }

    private func finishOnWrist(_ before: LiveWorkout, action: WorkoutAction, at date: Date) {
        let finished = before.applying(action, at: date)
        ended = LinkEnd(action == .finish ? finished : nil, at: date)
        if action == .finish {
            haptic(.finished)
        }
        if isAlone {
            linked = nil
        }
    }

    // MARK: What time does

    /// Saves, sends, and sets the clock for the next change.
    private func changed() {
        write(linked.flatMap { try? JSONEncoder().encode($0) })
        sendHeld()
        reschedule()
    }

    private func reschedule() {
        clock?.cancel()
        guard let live, let next = live.nextChange(after: now()) else { return }
        let wait = max(0, next.timeIntervalSince(now()))
        clock = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.tick()
        }
    }

    /// The moment the situation changes by itself: a rest or a "Start in" over, a timed set run
    /// out, or a count due.
    private func tick() {
        guard let live else { return }
        let date = now()
        let situation = live.situation(at: date)
        if case let .comingUp(set) = situation, !isAlone, isPhoneInReach {
            if dueSince?.set != set {
                dueSince = (set, date)
            }
            if let since = dueSince?.at, date.timeIntervalSince(since) < Self.countGrace {
                clock = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(Self.countGrace))
                    guard !Task.isCancelled else { return }
                    self?.tick()
                }
                return
            }
        }
        catchUp(live, at: date)
    }

    /// Turns what time did into actions: a timed set run out logged, the next count begun.
    private func catchUp(_ live: LiveWorkout, at date: Date) {
        let before = live.situation(at: date.addingTimeInterval(-0.05))
        var caught = live
        caught.workoutSession = live.caughtUp(at: date)
        if caught.workoutSession.count == live.workoutSession.count,
           caught.workoutSession.sets.count == live.workoutSession.sets.count
        {
            caught.workoutSession = live.beginningCount(at: date)
        }
        var linked = linked ?? LinkedWorkout()
        if caught.workoutSession.sets.count > live.workoutSession.sets.count,
           let logged = caught.workoutSession.sets.last
        {
            linked.act(.log(logged.planned), at: date)
            haptic(.setRanOut)
        } else {
            switch before {
            case .resting: haptic(.restEnded)
            case .countingIn: haptic(.startInEnded)
            default: break
            }
        }
        if let count = caught.workoutSession.count, count != live.workoutSession.count {
            linked.act(.beginCount(count), at: date)
        }
        self.linked = linked
        changed()
    }

    // MARK: The link

    private func handle(_ event: MirrorEvent) {
        switch event {
        case .connected:
            isPhoneInReach = true
            sendHeld()
        case let .received(data):
            isPhoneInReach = true
            receive(data)
        case .disconnected:
            isPhoneInReach = false
            retry()
        case .ended:
            break
        }
    }

    private func receive(_ data: Data) {
        guard let message = LinkMessage.decoded(from: data) else {
            Logger.watch.error("A message from the phone did not read")
            return
        }
        switch message.body {
        case .hello:
            send(.hello, session: message.session)
            if linked?.sessionID == message.session {
                sendHeld()
            }
        case let .state(state):
            var linked = linked ?? LinkedWorkout()
            linked.take(state, for: message.session)
            self.linked = linked.live == nil ? nil : linked
            if let live, !live.workoutSession.isInProgress {
                ended = LinkEnd(live.workoutSession, at: now())
                self.linked = nil
                Task { await mirror.end() }
            }
            write(self.linked.flatMap { try? JSONEncoder().encode($0) })
            reschedule()
        case let .ended(end):
            guard linked?.sessionID == message.session || linked == nil else { return }
            if end.finished || ended == nil {
                ended = end.finished ? end : nil
            }
            linked = nil
            write(nil)
            clock?.cancel()
            Task { await mirror.end() }
        case .actions:
            break
        }
    }

    /// Sends the actions the phone has not confirmed.
    private func sendHeld() {
        guard !isAlone, let linked, let session = linked.sessionID, !linked.pending.isEmpty
        else { return }
        send(.actions(linked.pending), session: session)
    }

    private func send(_ body: LinkMessage.Body, session: UUID) {
        guard !isAlone, let data = try? LinkMessage(session: session, body: body).encoded()
        else { return }
        let mirror = mirror
        Task { [weak self] in
            do {
                try await mirror.send(data)
                self?.isPhoneInReach = true
            } catch {
                self?.isPhoneInReach = false
                self?.retry()
            }
        }
    }

    /// While the phone is out of reach and actions are held, sends them again every 5 s.
    private func retry() {
        guard retrying == nil else { return }
        retrying = Task { [weak self] in
            while let self, !self.isPhoneInReach, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                sendHeld()
            }
            self?.retrying = nil
        }
    }
}

extension Logger {
    static let watch = Logger(subsystem: "com.plusplusinc.plusplus", category: "watch")
}
