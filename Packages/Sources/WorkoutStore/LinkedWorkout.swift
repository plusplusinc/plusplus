import Foundation

/// The Watch's whole copy of the workout: the phone's last word, then what the wrist did since
/// that the phone has not confirmed. `live` is always the one with the other applied in order,
/// so a state that left the phone before it heard of a tap never takes the tap off the wrist's
/// screen, and the state that includes it drops it from `pending` in the same step: none is
/// lost, since an action stays until confirmed, and none counts twice, since the phone applies
/// each by its number. Codable whole, as the Watch keeps it on disk through a relaunch.
public struct LinkedWorkout: Codable, Equatable, Sendable {
    /// The phone's last state, with the plan it last sent.
    public private(set) var base: LinkState?
    /// What the wrist did that the phone has not confirmed, in order.
    public private(set) var pending: [LinkAction] = []
    private var nextSeq = 1
    /// The workout session it is for, once known.
    public private(set) var sessionID: UUID?
    /// How the phone's workout ended, once it has.
    public private(set) var ended: LinkEnd?
    /// Discarded on the wrist, before the phone heard.
    public private(set) var isDiscarded = false

    public init() { }

    /// A workout the Watch runs alone, from Start, with no phone: the demo.
    public init(alone workout: Workout, startedAt date: Date) {
        let session = WorkoutSession(
            workoutID: workout.id,
            workoutName: workout.name,
            startedAt: date,
        )
        sessionID = session.id
        let landed = LiveWorkout(workout: workout, workoutSession: session).landingStart(at: date)
        base = LinkState(rev: 0, watchSeq: 0, plan: workout, session: landed)
    }

    /// The workout as it stands on the wrist: the phone's, with every pending action applied.
    /// Nil before the phone's first state with its plan, or once discarded.
    public var live: LiveWorkout? {
        guard !isDiscarded, let base, let plan = base.plan else { return nil }
        var live = LiveWorkout(workout: plan.workout, workoutSession: base.session.session)
        for action in pending {
            guard let wanted = action.action.action,
                  let session = live.applying(wanted, at: action.at)
            else { return nil }
            live.workoutSession = session
        }
        return live
    }

    /// The wrist did `action` at `date`: numbered, held, and shown at once.
    public mutating func act(_ action: WorkoutAction, at date: Date) {
        pending.append(LinkAction(seq: nextSeq, at: date, action: action))
        nextSeq += 1
        if action == .discard {
            isDiscarded = true
        }
    }

    /// The phone's state, for `session`: kept when it is newer than the one held, dropping what
    /// it confirms. A state with no plan keeps the plan held. A state for another workout
    /// session starts over on it.
    public mutating func take(_ state: LinkState, for session: UUID) {
        if session != sessionID {
            self = Self()
            sessionID = session
        }
        guard state.rev > base?.rev ?? -1 else { return }
        var state = state
        if state.plan == nil {
            state.plan = base?.plan
        }
        base = state
        pending.removeAll { $0.seq <= state.watchSeq }
        nextSeq = max(nextSeq, state.watchSeq + 1)
    }

    /// The phone's workout is over.
    public mutating func end(_ end: LinkEnd) {
        ended = end
        pending.removeAll()
    }
}
