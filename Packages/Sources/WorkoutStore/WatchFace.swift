import Foundation

/// What the Watch's set page shows at a moment, as plain values, so its views hold no rules: the
/// exercise's name and dot, its set bars, the caption under them, the big middle, and the key.
/// Read from `LiveWorkout.situation(at:)`, at the moment, so a view that reads it once a second
/// counts down with no tick stored.
public struct WatchFace: Equatable, Sendable {
    /// The dot before the name: green while a set is up, purple once the last is logged, gray
    /// while paused.
    public enum Dot: Equatable, Sendable {
        case active
        case done
        case quiet
    }

    /// One bar: a set logged (purple), the one up (green), or one to do (gray).
    public enum Bar: Equatable, Sendable {
        case done
        case current
        case toDo
    }

    /// The big middle of the page.
    public enum Middle: Equatable, Sendable {
        /// The set's numbers, each over what it counts: "5" "reps", "45" "lb".
        case figures([PlanFigure])
        /// A count with its label over it: "Start in" "0:05", "Rest" "0:28".
        case count(label: String, time: String)
        /// A timed set's own count, over the time it runs: "0:42" "of 1:00".
        case timed(time: String, of: String)
        /// Every set logged: "9 of 9" over "sets done in 24:10".
        case allLogged(count: String, detail: String)
    }

    /// The key at the bottom; nil through "Start in", which takes no log (as on the phone).
    public enum Key: Equatable, Sendable {
        /// Logs the set, saying what it logs: "Log set", "Log left".
        case log(String)
        /// Skip and +15, with the share of the rest run, which fills Skip.
        case rest(fill: Double)
        /// Logs a timed set before its count ends, with the share run, which fills it.
        case logEarly(fill: Double)
        case finish
        /// Resumes a paused workout: "Continue", as the phone's key says.
        case resume
    }

    public var name: String
    public var dot: Dot
    /// The exercise's sets in order, each one bar, or a pair of bars for one done a side at a
    /// time.
    public var bars: [[Bar]]
    public var caption: String
    public var middle: Middle
    public var key: Key?
    /// Paused: the middle reads quieter.
    public var isQuiet: Bool
}

extension LiveWorkout {
    /// The set page at `now`; nil with no workout in progress or nothing in it to do.
    public func watchFace(at now: Date, locale: Locale = .current) -> WatchFace? {
        guard var face = unpausedFace(at: now, locale: locale) else { return nil }
        if workoutSession.isPaused {
            face.dot = .quiet
            face.caption += " · " + String(localized: "Paused")
            face.key = .resume
            face.isQuiet = true
        }
        return face
    }

    private func unpausedFace(at now: Date, locale: Locale) -> WatchFace? {
        let clock = workoutSession.clock(at: now)
        switch situation(at: now) {
        case .notStarted, .nothingToDo:
            return nil
        case let .comingUp(set):
            let left = Double(workout.startIn(before: set))
            return setFace(set, locale: locale, middle: startIn(left, locale: locale), key: nil)
        case let .countingIn(count):
            let left = count.startClock - clock - Self.startInHold
            return setFace(
                count.set,
                locale: locale,
                middle: startIn(left, locale: locale),
                key: nil,
            )
        case let .doing(set, timed?):
            let left = timed.remaining(atClock: clock)
            let length = Double(timed.length)
            let of = String(localized: "of \(Self.countText(length, locale: locale))")
            let middle = WatchFace.Middle.timed(time: Self.countText(left, locale: locale), of: of)
            let key = WatchFace.Key.logEarly(fill: Self.share(run: length - left, of: length))
            return setFace(set, locale: locale, middle: middle, key: key)
        case let .doing(set, nil):
            let figures = row(of: set)?.shownFigures(side: set.side, locale: locale) ?? []
            let key = logText.map { WatchFace.Key.log($0) }
            return setFace(set, locale: locale, middle: .figures(figures), key: key)
        case let .resting(rest):
            let time = Self.countText(rest.shownLeft(atClock: clock), locale: locale)
            let run = (rest.skippedAt ?? clock) - rest.startClock
            let key = WatchFace.Key.rest(fill: Self.share(run: run, of: Double(rest.length)))
            let middle = WatchFace.Middle.count(label: String(localized: "Rest"), time: time)
            return doneFace(after: rest.after, locale: locale, middle: middle, key: key)
        case .allLogged:
            return allLoggedFace(at: now, locale: locale)
        }
    }

    private func startIn(_ left: Double, locale: Locale) -> WatchFace.Middle {
        .count(label: String(localized: "Start in"), time: Self.countText(left, locale: locale))
    }

    /// After the last set: "9 of 9" "sets done in 24:10", and Finish.
    private func allLoggedFace(at now: Date, locale: Locale) -> WatchFace? {
        guard let last = workoutSession.sets.last else { return nil }
        let total = workout.setOrder.count
        let elapsed = WorkoutSession.elapsedText(workoutSession.elapsed(at: now), locale: locale)
        let middle = WatchFace.Middle.allLogged(
            count: String(localized: "\(workoutSession.sets.count) of \(total)"),
            detail: String(localized: "sets done in \(elapsed)"),
        )
        return doneFace(after: last.planned, locale: locale, middle: middle, key: .finish)
    }

    /// The page with `set` up: its bars green at it, its caption "Set 2 of 3 · Left".
    private func setFace(
        _ set: PlannedSet,
        locale: Locale,
        middle: WatchFace.Middle,
        key: WatchFace.Key?,
    ) -> WatchFace {
        var caption = place(of: set, locale: locale)
        if let side = set.side {
            caption += " · " + side.text
        }
        return WatchFace(
            name: row(of: set)?.exercise.name ?? "",
            dot: .active,
            bars: bars(of: set.row, upTo: set),
            caption: caption,
            middle: middle,
            key: key,
            isQuiet: false,
        )
    }

    /// The page just after `set` was logged: its bars purple through it, its caption
    /// "Set 1 of 3 done".
    private func doneFace(
        after set: PlannedSet,
        locale: Locale,
        middle: WatchFace.Middle,
        key: WatchFace.Key?,
    ) -> WatchFace {
        let lastOfAll = currentSet == nil
        return WatchFace(
            name: row(of: set)?.exercise.name ?? "",
            dot: lastOfAll ? .done : .active,
            bars: bars(of: set.row, upTo: nil),
            caption: place(of: set, locale: locale) + " " + String(localized: "done"),
            middle: middle,
            key: key,
            isQuiet: false,
        )
    }

    /// "Set 2 of 3", or "Round 2 of 3" in a superset.
    private func place(of set: PlannedSet, locale: Locale) -> String {
        let word = WorkoutExercise.progressWord(inSuperset: workout.isInSuperset(set.row))
        let total = row(of: set)?.plan.sets ?? 0
        return "\(word) \(set.round.formatted(.number.locale(locale))) of "
            + total.formatted(.number.locale(locale))
    }

    /// The row's bars: each set's sides purple once logged, `current` green, the rest gray.
    private func bars(of id: WorkoutExercise.ID, upTo current: PlannedSet?) -> [[WatchFace.Bar]] {
        guard let item = workout.exercises.first(where: { $0.id == id }) else { return [] }
        let logged = Set(workoutSession.sets.map(\.planned))
        return (1 ... max(1, item.plan.sets)).map { round in
            item.sides.map { side in
                let set = PlannedSet(row: id, round: round, side: side)
                if logged.contains(set) {
                    return .done
                }
                return set == current ? .current : .toDo
            }
        }
    }

    private func row(of set: PlannedSet) -> WorkoutExercise? {
        workout.exercises.first { $0.id == set.row }
    }

    /// A count as it reads, whole seconds rounded up so 0:00 shows only at the end: "0:05".
    static func countText(_ seconds: Double, locale: Locale) -> String {
        Duration.seconds(max(0, seconds).rounded(.up))
            .formatted(.time(pattern: .minuteSecond).locale(locale))
    }

    private static func share(run: Double, of length: Double) -> Double {
        length > 0 ? min(1, max(0, run / length)) : 1
    }
}
