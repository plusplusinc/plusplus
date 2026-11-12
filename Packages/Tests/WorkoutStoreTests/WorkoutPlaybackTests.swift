import Foundation
import Testing
@testable import WorkoutStore

/// The steps a screen plays for the sets logged, one at a time, in order.
@Suite("Workout playback")
struct WorkoutPlaybackTests {
    private let row = UUID()
    private let other = UUID()

    private func set(_ round: Int) -> PlannedSet {
        PlannedSet(row: row, round: round)
    }

    private var down: LiveWorkout.Step {
        .nextExercise(to: PlannedSet(row: other, round: 1), isBack: false, startsRound: false)
    }

    @Test("A log at rest starts its step now")
    func logAtRest() {
        var playback = WorkoutPlayback()
        let startsNow = playback.log(set(1))
        #expect(startsNow)
        #expect(playback.unshown == [set(1)])
    }

    @Test("A log while a step plays waits, and plays when that step ends")
    func logWhilePlaying() {
        var playback = WorkoutPlayback()
        _ = playback.log(set(1))
        playback.start(down, for: set(1))
        playback.show()
        let startsNow = playback.log(set(2))
        #expect(!startsNow, "A step is playing")
        #expect(playback.unshown == [set(2)], "Stored, not dropped, and not drawn")
        let next = playback.end()
        #expect(next == set(2))
        playback.start(.nextSet, for: set(2))
        playback.show()
        let after = playback.end()
        #expect(after == nil)
        #expect(playback.unshown.isEmpty)
    }

    @Test("Two logs waiting play oldest first")
    func queueOrder() {
        var playback = WorkoutPlayback()
        _ = playback.log(set(1))
        playback.start(down, for: set(1))
        _ = playback.log(set(2))
        _ = playback.log(set(3))
        playback.show()
        let first = playback.end()
        #expect(first == set(2))
        playback.start(.nextSet, for: set(2))
        playback.show()
        let second = playback.end()
        #expect(second == set(3))
    }

    @Test("Showing draws the playing step's set and no waiting one")
    func show() {
        var playback = WorkoutPlayback()
        _ = playback.log(set(1))
        playback.start(down, for: set(1))
        _ = playback.log(set(2))
        #expect(playback.unshown == [set(1), set(2)])
        playback.show()
        #expect(playback.unshown == [set(2)])
        #expect(playback.playing?.set == set(1), "Still playing until it ends")
    }

    @Test("Only a step to another exercise, or the last, is moving on")
    func movingOn() {
        var playback = WorkoutPlayback()
        #expect(!playback.isMovingOn)
        _ = playback.log(set(1))
        playback.start(.nextSet, for: set(1))
        #expect(!playback.isMovingOn)
        playback.start(down, for: set(1))
        #expect(playback.isMovingOn)
        playback.start(.last, for: set(1))
        #expect(playback.isMovingOn)
        _ = playback.end()
        #expect(!playback.isMovingOn)
    }

    @Test("A set is held only while its step stays on the exercise and has not shown")
    func held() {
        var playback = WorkoutPlayback()
        _ = playback.log(set(1))
        #expect(playback.held == nil, "Not before its step starts")
        playback.start(.nextSet, for: set(1))
        #expect(playback.held == set(1))
        playback.show()
        #expect(playback.held == nil)
        _ = playback.end()
        _ = playback.log(set(2))
        playback.start(down, for: set(2))
        #expect(playback.held == nil, "A move is not a hold")
    }
}
