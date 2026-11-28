import Foundation
import Testing
@testable import WorkoutStore

extension WorkoutPhaseTests {
    static let workoutSession = WorkoutSession(workoutID: UUID(), workoutName: "", startedAt: .now)

    /// A transition of Start's or End's, by name.
    enum Step {
        case pressStart
        case grow
        case landStart
        case fadeIn
        case run
        case keyLeaves
        case timeFades
        case rest

        func apply(to phase: inout WorkoutPhase) -> Bool {
            switch self {
            case .pressStart: phase.pressStart()
            case .grow: phase.grow()
            case .landStart: phase.landStart()
            case .fadeIn: phase.fadeIn()
            case .run: phase.run(on: nil)
            case .keyLeaves: phase.keyLeaves()
            case .timeFades: phase.timeFades()
            case .rest: phase.rest()
            }
        }
    }

    /// Applies `steps` in turn to `phase`: whether each applied. A step that does not apply
    /// leaves the phase as it was.
    static func applying(_ steps: [Step], to phase: inout WorkoutPhase) -> [Bool] {
        steps.map { step in
            let before = phase
            let applied = step.apply(to: &phase)
            if !applied {
                #expect(phase == before, "\(step) changed \(before)")
            }
            return applied
        }
    }

    /// Start's and End's phases, at every beat.
    static var startAndEnd: [WorkoutPhase] {
        var leaving = ending(from: .running)
        _ = applying([.keyLeaves], to: &leaving)
        var timeGone = leaving
        _ = applying([.timeFades], to: &timeGone)
        return [
            .starting(.pressed),
            .starting(.growing),
            .starting(.landed),
            .starting(.fadingIn),
            ending(from: .running),
            leaving,
            timeGone,
        ]
    }

    static func isEnding(_ phase: WorkoutPhase) -> Bool {
        if case .ending = phase {
            return true
        }
        return false
    }

    static func ending(from phase: WorkoutPhase) -> WorkoutPhase {
        var ended = phase
        // One moment for every ending, so two endings of one phase are equal.
        ended.end(workoutSession, at: workoutSession.startedAt)
        return ended
    }

    @Test("Start is pressed only out of a workout, and a second press changes nothing")
    func pressStart() {
        var phase = WorkoutPhase.idle
        #expect(Self.applying([.pressStart, .pressStart], to: &phase) == [true, false])
        #expect(phase == .starting(.pressed))
        #expect(phase.isStarting)
        for other in Self.everyPhase + Self.startAndEnd where other != .idle {
            var pressed = other
            #expect(Self.applying([.pressStart], to: &pressed) == [false], "\(other)")
        }
    }

    @Test("Start's beats apply only in order; with no motion it fades in from the press")
    func startBeats() {
        var phase = WorkoutPhase.starting(.pressed)
        #expect(Self.applying([.landStart, .run, .grow], to: &phase) == [false, false, true])
        #expect(phase.isStarting, "The key is Start's while the first exercise grows")
        #expect(Self.applying([.fadeIn, .run, .landStart], to: &phase) == [false, false, true])
        #expect(!phase.isStarting)
        #expect(phase.isOnWayIn, "Landed, the screen is still on its way to the first set")
        #expect(Self.applying([.grow, .run], to: &phase) == [false, true])
        #expect(phase == .running)
        #expect(!phase.isOnWayIn)

        var fading = WorkoutPhase.starting(.pressed)
        #expect(Self.applying([.fadeIn, .landStart], to: &fading) == [true, false])
        #expect(!fading.isStarting)
        #expect(fading.isOnWayIn)
        #expect(Self.applying([.run], to: &fading) == [true])
        #expect(fading == .running)
    }

    @Test("Starting and ending are not moving on: no log is shown, and the room isn't a landing's")
    func startAndEndAreNotMovingOn() {
        for phase in Self.startAndEnd {
            #expect(!phase.isMovingOn, "\(phase)")
        }
    }

    @Test("The key is gone, its room kept as Start lands, given up as Start fades in or End goes")
    func keyGone() {
        #expect(WorkoutPhase.starting(.landed).keyGone == .keepingRoom)
        #expect(WorkoutPhase.starting(.fadingIn).keyGone == .givingUpRoom)
        var phase = Self.ending(from: .running)
        #expect(phase.keyGone == nil, "The key leaves in a transaction of its own")
        _ = Self.applying([.keyLeaves], to: &phase)
        #expect(phase.keyGone == .givingUpRoom)
        _ = Self.applying([.timeFades], to: &phase)
        #expect(phase.keyGone == .givingUpRoom)
        for other in Self.everyPhase + [.starting(.pressed), .starting(.growing)] {
            #expect(other.keyGone == nil, "\(other)")
        }
    }

    @Test("End applies from every phase with a workout, and from none without")
    func endFromEveryPhase() {
        let without: [WorkoutPhase] = [.idle, .starting(.pressed)]
            + Self.startAndEnd.filter(Self.isEnding)
        for phase in Self.everyPhase + Self.startAndEnd {
            var ended = phase
            let applied = ended.end(Self.workoutSession)
            if without.contains(phase) {
                #expect(!applied, "\(phase)")
                #expect(ended == phase)
            } else {
                #expect(applied, "\(phase)")
                #expect(Self.isEnding(ended))
                #expect(ended.endingWorkoutSession == Self.workoutSession)
                #expect(!ended.takesLog)
                #expect(!ended.isMovingOn)
                #expect(ended.move == nil)
                #expect(ended.keySet == nil)
            }
        }
    }

    @Test(
        "End keeps the screen as drawn: a set not yet drawn stays hidden, a move's until it shifts",
    )
    func endKeepsWhatIsDrawn() {
        #expect(Self.ending(from: Self.logging(.nextSet)).hidden == [Self.logged])
        let move = Self.logging(Self.down)
        for beats in [[], [.show], [.show, .land]] as [[Beat]] {
            let ended = Self.ending(from: Self.after(beats, from: move))
            #expect(ended.hidden == [Self.logged], "\(beats)")
        }
        for beats in [[.show, .land, .shift], [.show, .land, .shift, .roll]] as [[Beat]] {
            #expect(Self.ending(from: Self.after(beats, from: move)).hidden.isEmpty, "\(beats)")
        }
        for (step, moves) in [(LiveWorkout.Step.last, true), (Self.down, false)] {
            let phase = Self.logging(step, moves: moves)
            #expect(Self.ending(from: phase).hidden == [Self.logged])
            #expect(Self.ending(from: Self.after([.show], from: phase)).hidden.isEmpty)
        }
        #expect(Self.ending(from: .running).hidden.isEmpty)
    }

    @Test("Once ending, a beat of the sequence End took over changes nothing")
    func endingRefusesBeats() {
        let ended = Self.ending(from: Self.after([.show, .land], from: Self.logging(Self.down)))
        for beat in Beat.allCases {
            var tried = ended
            let applied = Self.apply(beat, to: &tried)
            #expect(!applied, "\(beat)")
            #expect(tried == ended)
        }
        var tried = ended
        #expect(Self.applying([.grow, .landStart, .run], to: &tried) == [false, false, false])
        let logged = tried.log(Self.logged, leadingTo: .nextSet, moves: true)
        #expect(!logged)
        #expect(tried == ended)
    }

    @Test("Ended at once in the store, the workout is drawn as it was until the list leaves it")
    func drawnUntilTheListLeaves() {
        let notEnding = Self.everyPhase + Self.startAndEnd.filter { !Self.isEnding($0) }
        for phase in notEnding {
            #expect(phase.drawnWorkoutSession == nil, "\(phase)")
        }
        var phase = Self.ending(from: Self.logging(.nextSet))
        #expect(phase.drawnWorkoutSession == Self.workoutSession)
        #expect(
            phase.hidden == [Self.logged],
            "Drawn as it was, the set not yet shown stays hidden",
        )
        _ = Self.applying([.keyLeaves], to: &phase)
        #expect(
            phase.drawnWorkoutSession == Self.workoutSession,
            "The key's beats leave the list as it is",
        )
        let left = phase.listLeaves()
        #expect(left)
        #expect(phase.drawnWorkoutSession == nil)
        #expect(
            phase.endingWorkoutSession == Self.workoutSession,
            "The bar's time stays until it fades",
        )
        let leftAgain = phase.listLeaves()
        #expect(!leftAgain)
        for other in notEnding {
            var tried = other
            let applied = tried.listLeaves()
            #expect(!applied, "\(other)")
            #expect(tried == other)
        }
    }

    @Test("Drawn after End, the workout's rest holds where End came, until the list leaves it")
    func drawnEnd() {
        let came = Date.now
        var phase = Self.logging(.nextSet)
        #expect(phase.drawnEnd == nil)
        phase.end(Self.workoutSession, at: came)
        #expect(phase.drawnEnd == came)
        _ = Self.applying([.keyLeaves], to: &phase)
        #expect(phase.drawnEnd == came, "The key's beats leave the rest held")
        phase.listLeaves()
        #expect(phase.drawnEnd == nil)
    }

    @Test("An ending's beats apply in order; the time shows until it fades; then out of a workout")
    func endingBeats() {
        var phase = Self.ending(from: .running)
        #expect(Self.applying([.timeFades, .rest, .keyLeaves], to: &phase) == [false, false, true])
        #expect(phase.endingWorkoutSession == Self.workoutSession)
        #expect(Self.applying([.keyLeaves, .rest, .timeFades], to: &phase) == [false, false, true])
        #expect(phase.endingWorkoutSession == nil)
        #expect(Self.applying([.rest], to: &phase) == [true])
        #expect(phase == .idle)
    }

    /// A finish holds the screen at the ending's first beat, under its "++" and the way to Log:
    /// the key up, the workout drawn as it was, until the key leaves.
    @Test("An ending begun holds the key up and the workout drawn, until the key leaves")
    func endBegunHolds() {
        for phase in Self.everyPhase + Self.startAndEnd.filter({ !Self.isEnding($0) }) {
            #expect(!phase.isEndBegun, "\(phase)")
        }
        var phase = Self.ending(from: Self.logging(.nextSet))
        #expect(phase.isEndBegun)
        #expect(phase.keyGone == nil, "the key stays up")
        #expect(phase.drawnWorkoutSession == Self.workoutSession)
        _ = Self.applying([.keyLeaves], to: &phase)
        #expect(!phase.isEndBegun)
    }
}
