import WorkoutStore

extension AppSession {
    /// Where the app is, under the drawer.
    public enum Screen: Equatable {
        /// The open workout, at the root: as launched, and once it starts.
        case workout
        /// The Workouts screen, its list showing.
        case workouts
        /// The open workout, pushed onto the Workouts screen from its list.
        case pushedWorkout
        /// Log, its tabs showing.
        case log
        /// A finished logged workout, pushed onto Log from its History tab.
        case loggedWorkout(LoggedWorkout.ID)

        /// Whether something is pushed, so the edge swipe goes back rather than opening the
        /// drawer.
        public var isPushed: Bool {
            switch self {
            case .pushedWorkout, .loggedWorkout: true
            case .workout, .workouts, .log: false
            }
        }
    }

    /// Shows the Workouts screen and closes the drawer.
    public func showWorkouts() {
        endThroughDrawer()
        screen = .workouts
        closeDrawer()
    }

    /// Shows `place` by way of the drawer, so the eye sees where it went. From a closed drawer,
    /// as Log's Go to Workouts goes, the drawer first opens with its own motion, marking the
    /// place showing, and is held open longer: the mark waits until the slide has visibly
    /// arrived plus a hold (`opening.arrival` + `opening.holdBefore`), and stays on `place`
    /// for `opening.holdAfter` once it has landed. From an open one, as a drawer row is tapped,
    /// the mark sets off at once and nothing is held. The mark moves to `place` (`drawerMark`);
    /// once it has landed (`markWait` later, plus any hold) the place swaps and the drawer
    /// closes over it. Each beat sleeps to a deadline from the start.
    ///
    /// One plays at a time; another asked for meanwhile is ignored. Anything that closes the
    /// drawer mid-way, a tap beside it or a swipe, ends it on `place` (`closeDrawer()`). Where
    /// the drawer is kept shut it goes straight there.
    ///
    /// With a `lead`, as after a finish's "++", the way waits that long before the drawer opens,
    /// `place` pending from the call, so whatever ends a way ends the wait too.
    public func show(
        _ place: Showing,
        after lead: Duration = .zero,
        throughDrawer opening: DrawerOpening,
        markWait: Duration,
    ) {
        guard throughDrawerPlace == nil else { return }
        throughDrawerPlace = place
        guard lead > .zero else {
            openWay(to: place, opening: opening, markWait: markWait)
            return
        }
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
        var markAt = Duration.zero
        var closeAt = markWait
        // From an open drawer the mark moves on the beats' first turn, as from a closed one,
        // so both starts take one path.
        if !isDrawerOpen {
            drawerMark = nil
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

    /// Ends a way through the drawer that hasn't finished, as the app leaves the foreground: it
    /// lands where it was going with the drawer closed. Does nothing when none is under way.
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
    public func popWorkout() {
        if screen == .pushedWorkout {
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
        case .log, .loggedWorkout: .log
        case .workout, .pushedWorkout: .workout
        }
    }

    /// The beats of a drawer opened for a way through it (`show(_:throughDrawer:markWait:)`):
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
}
