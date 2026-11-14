import Foundation
import Testing
@testable import WorkoutStore

/// Where a workout on the routine screen is in its sequence, and what a log shows in turn.
@Suite("Workout phase")
struct WorkoutPhaseTests {
    private static let row = UUID()
    private static let other = UUID()
    static let logged = PlannedSet(row: row, round: 1)
    private static let next = PlannedSet(row: other, round: 1)

    static let down = LiveWorkout.Step.nextExercise(
        to: next,
        isBack: false,
        startsRound: false,
    )
    private static let round = LiveWorkout.Step.nextExercise(
        to: PlannedSet(row: other, round: 2),
        isBack: true,
        startsRound: true,
    )

    /// A beat of a sequence, applied by name.
    enum Beat: CaseIterable {
        case show
        case land
        case shift
        case roll
        case settle
    }

    /// Applies `beat` to `phase`: whether it changed it.
    static func apply(_ beat: Beat, to phase: inout WorkoutPhase) -> Bool {
        switch beat {
        case .show: phase.show()
        case .land: phase.land()
        case .shift: phase.shift()
        case .roll: phase.roll()
        case .settle: phase.settle()
        }
    }

    /// `phase` after `beats`, each of which must apply.
    static func after(_ beats: [Beat], from phase: WorkoutPhase) -> WorkoutPhase {
        var phase = phase
        for beat in beats {
            let applied = apply(beat, to: &phase)
            #expect(applied, "\(beat) from \(phase)")
        }
        return phase
    }

    static func logging(_ step: LiveWorkout.Step, moves: Bool = true) -> WorkoutPhase {
        var phase = WorkoutPhase.running
        phase.log(logged, leadingTo: step, moves: moves)
        return phase
    }

    /// One of each phase, at every beat a sequence passes through.
    static var everyPhase: [WorkoutPhase] {
        let move = logging(down)
        let others = [(LiveWorkout.Step.last, true), (down, false), (.last, false)].flatMap {
            let phase = logging($0, moves: $1)
            return [phase, after([.show], from: phase)]
        }
        return [
            .idle,
            .running,
            logging(.nextSet),
            move,
            after([.show], from: move),
            after([.show, .land], from: move),
            after([.show, .land, .shift, .roll], from: move),
        ] + others
    }

    @Test("A screen opens idle with no workout, at rest with one")
    func opening() {
        #expect(WorkoutPhase(hasWorkout: false) == .idle)
        #expect(WorkoutPhase(hasWorkout: true) == .running)
    }

    @Test("A log is taken only at rest; anywhere else it changes nothing")
    func logOnlyAtRest() {
        for phase in Self.everyPhase where phase != .running {
            #expect(!phase.takesLog, "\(phase)")
            var logged = phase
            let took = logged.log(Self.next, leadingTo: .nextSet, moves: true)
            #expect(!took, "\(phase)")
            #expect(logged == phase)
        }
        #expect(WorkoutPhase.running.takesLog)
    }

    @Test("A log that stays on its exercise is held and hidden until shown, then at rest")
    func held() {
        let phase = Self.logging(.nextSet)
        #expect(phase.held == Self.logged)
        #expect(phase.hidden == [Self.logged])
        #expect(!phase.isMovingOn)
        let shown = Self.after([.show], from: phase)
        #expect(shown == .running)
        #expect(shown.held == nil)
        #expect(shown.hidden.isEmpty)
    }

    @Test("A move is hidden until shown, its node unlit until landed, its beats only in order")
    func move() throws {
        let order: [Beat] = [.show, .land, .shift, .roll, .settle]
        var phase = Self.logging(Self.down)
        #expect(phase.isMovingOn)
        #expect(phase.hidden == [Self.logged])
        for (index, beat) in order.enumerated() {
            for other in Beat.allCases where other != beat {
                var tried = phase
                let applied = Self.apply(other, to: &tried)
                #expect(!applied, "\(other) before \(beat)")
                #expect(tried == phase)
            }
            if beat == .land {
                #expect(try #require(phase.move).isLanded == false)
            }
            let applied = Self.apply(beat, to: &phase)
            #expect(applied, "\(beat), beat \(index)")
            if beat == .show {
                #expect(phase.hidden.isEmpty)
            }
            if beat == .land {
                #expect(try #require(phase.move).isLanded)
            }
        }
        #expect(phase == .running)
        #expect(phase.move == nil)
    }

    @Test("The key keeps the logged set's words until the roll, through a close or fade until over")
    func keySet() {
        let move = Self.logging(Self.down)
        for beats in [[], [.show], [.show, .land]] as [[Beat]] {
            #expect(Self.after(beats, from: move).keySet == Self.logged, "\(beats)")
        }
        #expect(Self.after([.show, .land, .shift, .roll], from: move).keySet == nil)
        for (step, moves) in [(LiveWorkout.Step.last, true), (Self.down, false), (.last, false)] {
            let phase = Self.logging(step, moves: moves)
            #expect(phase.keySet == Self.logged)
            #expect(Self.after([.show], from: phase).keySet == Self.logged)
            #expect(Self.after([.show, .settle], from: phase).keySet == nil)
        }
        #expect(Self.logging(.nextSet).keySet == nil, "A held set's key reads the workout drawn")
    }

    @Test("A round is held only on a move that starts one, and only until the roll")
    func roundHeld() throws {
        let phase = Self.logging(Self.round)
        #expect(try #require(phase.move).holdsRound)
        #expect(try #require(Self.after([.show, .land], from: phase).move).holdsRound)
        let rolled = Self.after([.show, .land, .shift, .roll], from: phase)
        #expect(try #require(rolled.move).holdsRound == false)
        #expect(try #require(Self.logging(Self.down).move).holdsRound == false)
    }

    @Test("The last set closes, settling only once shown; with no motion it fades on")
    func last() {
        var phase = Self.logging(.last)
        #expect(phase == .closing(Self.logged, isShown: false))
        #expect(phase.isMovingOn)
        #expect(phase.hidden == [Self.logged])
        let settledEarly = phase.settle()
        #expect(!settledEarly, "Not before it shows")
        phase = Self.after([.show], from: phase)
        #expect(phase == .closing(Self.logged, isShown: true))
        #expect(phase.hidden.isEmpty)
        phase = Self.after([.settle], from: phase)
        #expect(phase == .running)
        let fading = Self.logging(.last, moves: false)
        #expect(fading == .fadingOn(Self.logged, isShown: false))
        #expect(fading.isMovingOn)
        #expect(fading.move == nil)
    }

    @Test("A close or a fade settles only once shown, and shows only once")
    func closeAndFadeBeats() {
        for (step, moves) in [(LiveWorkout.Step.last, true), (Self.down, false), (.last, false)] {
            var phase = Self.logging(step, moves: moves)
            let logged = phase
            let settledEarly = phase.settle()
            #expect(!settledEarly, "Not before it shows: \(logged)")
            #expect(phase == logged)
            phase = Self.after([.show], from: phase)
            let shown = phase
            let shownAgain = phase.show()
            #expect(!shownAgain, "\(shown)")
            #expect(phase == shown)
        }
    }

    @Test("With no motion, a step to another exercise has no move: nothing unlit, no round held")
    func noMotion() {
        let phase = Self.logging(Self.round, moves: false)
        #expect(phase.move == nil)
        #expect(phase.isMovingOn)
        #expect(phase.hidden == [Self.logged])
        let shown = Self.after([.show], from: phase)
        #expect(shown.hidden.isEmpty)
        #expect(Self.after([.settle], from: shown) == .running)
    }

    @Test("Stopped at once, each phase is where its sequence was going")
    func settleAtOnce() {
        for phase in Self.everyPhase + Self.startAndEnd {
            var stopped = phase
            stopped.settleAtOnce()
            let workoutGoes = phase == .idle || phase == .starting(.pressed) || phase.isEnding
            #expect(stopped == (workoutGoes ? .idle : .running), "\(phase)")
        }
    }
}
