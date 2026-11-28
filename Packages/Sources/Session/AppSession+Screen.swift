import WorkoutStore

extension AppSession {
    /// Where the app is, under the drawer.
    public enum Screen: Equatable {
        /// The open workout, at the root, as launched.
        case workout
        /// The Workouts screen, its list showing.
        case workouts
        /// The open workout, pushed onto the Workouts screen from its list.
        case pushedWorkout
        /// Log, its tabs showing.
        case log
        /// A finished workout session, pushed onto Log from its History tab.
        case workoutSession(WorkoutSession.ID)

        /// Whether something is pushed, so the edge swipe goes back rather than opening the
        /// drawer.
        public var isPushed: Bool {
            switch self {
            case .pushedWorkout, .workoutSession: true
            case .workout, .workouts, .log: false
            }
        }
    }

    /// While a workout is in progress, and through a way's lead, as a finish's before Log
    /// (`isLeadPending`), the drawer stays shut: neither ++ nor a swipe opens it, only the way.
    public var isDrawerLocked: Bool {
        workoutSession != nil || isLeadPending
    }

    /// Shows the Workouts screen and closes the drawer. A finish's way to Log that this cuts
    /// short leaves no workout for Log to bring in: kept, a Log days later left it out of
    /// History, then brought it in.
    public func showWorkouts() {
        endThroughDrawer()
        justFinished = nil
        screen = .workouts
        closeDrawer()
    }

    /// Shows `place` by way of the drawer, so the eye sees where it went. From a closed drawer,
    /// as Log's Go to Workouts and a finish go, the drawer first opens with its own motion,
    /// marking the place showing, and is held open longer: the mark waits until the slide has
    /// visibly arrived plus a hold (`opening.arrival` + `opening.holdBefore`), and stays on
    /// `place` for `opening.holdAfter` more once it has landed. From an open one, as a drawer
    /// row is tapped, the mark sets off at once. The mark moves to `place` (`drawerMark`); once
    /// `markWait` has passed, the caller's wait for the mark to land and rest there, plus any
    /// hold, the place swaps and the drawer closes over it. Each beat sleeps to a deadline from
    /// the start.
    ///
    /// One plays at a time; another asked for meanwhile is ignored. Anything that closes the
    /// drawer mid-way, a tap beside it or a swipe, ends it on `place` (`closeDrawer()`). Where
    /// the drawer is kept shut it goes straight there.
    ///
    /// With a `lead`, as after a finish's "++", the way waits that long before the drawer opens,
    /// `place` pending from the call, so whatever ends a way ends the wait too. Through the lead
    /// the drawer is locked (`isDrawerLocked`), so only the way opens it.
    public func show(
        _ place: Showing,
        after lead: Duration = .zero,
        throughDrawer opening: DrawerOpening,
        markWait: Duration,
    ) {
        guard throughDrawerPlace == nil else { return }
        // Here, since the way's own opening keeps its mark (`startShowingDrawer()`): a mark a way
        // before left goes, so the drawer opens marking what shows.
        if !isDrawerOpen {
            drawerMark = nil
        }
        throughDrawerPlace = place
        guard lead > .zero else {
            openWay(to: place, opening: opening, markWait: markWait)
            return
        }
        isLeadPending = true
        throughDrawer = wait(lead, on: beatClock) { [weak self] in
            self?.openWay(to: place, opening: opening, markWait: markWait)
        }
    }

    /// Runs `then` once `lead` has passed on `clock`, unless cancelled first.
    private func wait(
        _ lead: Duration,
        on clock: some Clock<Duration>,
        then: @escaping @MainActor () -> Void,
    ) -> Task<Void, Never> {
        let wake = clock.now.advanced(by: lead)
        return Task {
            do {
                try await clock.sleep(until: wake, tolerance: .zero)
                try Task.checkCancellation()
                then()
            } catch {
                // Cancelled: what ended the way has put the app where it goes.
            }
        }
    }

    /// The way's start, once any lead is over: the drawer opens if it is shut, and its beats
    /// begin.
    private func openWay(to place: Showing, opening: DrawerOpening, markWait: Duration) {
        isLeadPending = false
        var markAt = Duration.zero
        var closeAt = markWait
        // From an open drawer the mark moves on the beats' first turn, as from a closed one,
        // so both starts take one path.
        if !isDrawerOpen {
            openDrawer()
            guard isDrawerOpen else {
                closeDrawer()
                return
            }
            markAt = opening.arrival + opening.holdBefore
            closeAt = markAt + markWait + opening.holdAfter
        }
        throughDrawer = beats(on: beatClock, markingAt: markAt, closingAt: closeAt, place: place)
    }

    /// The way's two beats, each a sleep to a deadline from now on `clock`: the mark moves to
    /// `place`, then the drawer closes.
    private func beats(
        on clock: some Clock<Duration>,
        markingAt markAt: Duration,
        closingAt closeAt: Duration,
        place: Showing,
    ) -> Task<Void, Never> {
        let start = clock.now
        return Task { [weak self] in
            do {
                try await clock.sleep(until: start.advanced(by: markAt), tolerance: .zero)
                try Task.checkCancellation()
                self?.drawerMark = place
                try await clock.sleep(until: start.advanced(by: closeAt), tolerance: .zero)
                try Task.checkCancellation()
                self?.closeDrawer()
            } catch {
                // Cancelled: what ended the way has put the app where it goes.
            }
        }
    }

    /// Ends a way through the drawer that hasn't finished, its lead included, as the app leaves
    /// the foreground: it lands where it was going with the drawer closed. Does nothing when none
    /// is under way.
    public func finishThroughDrawer() {
        guard throughDrawerPlace != nil else { return }
        closeDrawer()
    }

    /// A drawer starting to show marks what shows now, not where a finished way went.
    func startShowingDrawer() {
        if !isDrawerOpen, throughDrawerPlace == nil {
            drawerMark = nil
        }
    }

    /// Stops a way through the drawer, leaving the place and the drawer to the caller, and the
    /// mark where it got to until the drawer next starts to show.
    func endThroughDrawer() {
        throughDrawer?.cancel()
        throughDrawer = nil
        throughDrawerPlace = nil
        // Observed: written only when it changes, so the many ends with no lead redraw nothing.
        if isLeadPending {
            isLeadPending = false
        }
    }

    /// Puts `place` under the drawer: a workout is no place the drawer goes, so it changes
    /// nothing.
    func land(on place: Showing) {
        switch place {
        case .workouts: screen = .workouts
        case .log: screen = .log
        case .workout: break
        }
    }

    /// Pops the workout pushed onto the Workouts screen, showing the list again, as its back
    /// button and back swipe do. A push goes through `open` or `startNew`. Add exercise goes
    /// with the workout, and so does New's ask to open it: a sheet set as a back swipe ends,
    /// with nothing left to show it, would otherwise come up over the next workout shown.
    /// Refused while a workout is in progress, which nothing leaves until it ends.
    public func popWorkout() {
        if screen == .pushedWorkout, workoutSession == nil {
            screen = .workouts
            opensAddExerciseOnShow = false
            addExercise = nil
        }
    }

    /// The place showing: the Workouts screen, Log, or a workout, which the drawer marks as
    /// Workouts while its row still goes to the list.
    public var showing: Showing {
        switch screen {
        case .workouts: .workouts
        case .log, .workoutSession: .log
        case .workout, .pushedWorkout: .workout
        }
    }

    /// The beats of a drawer opened for a way through it (`show(_:after:throughDrawer:markWait:)`):
    /// when its slide has visibly arrived, and how long it is held open before the mark moves
    /// and after it lands.
    public struct DrawerOpening: Sendable {
        let arrival: Duration
        let holdBefore: Duration
        let holdAfter: Duration

        public init(arrival: Duration, holdBefore: Duration, holdAfter: Duration) {
            self.arrival = arrival
            self.holdBefore = holdBefore
            self.holdAfter = holdAfter
        }
    }

    public enum Showing {
        case workouts
        case log
        case workout
    }

    /// Whether the open workout has anything to delete, for the workout screen's Delete: one
    /// with nothing saved has none, and one in progress is not deleted (`delete(_:)`).
    public var canDeleteOpen: Bool {
        !current.isEmpty && workoutSession == nil
    }
}
