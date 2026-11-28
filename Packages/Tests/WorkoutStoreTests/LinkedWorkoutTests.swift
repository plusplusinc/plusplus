import Foundation
import Testing
@testable import WorkoutStore

/// The Watch's copy of the workout, the actions both devices apply, and the link's messages.
@Suite("Linked workout")
struct LinkedWorkoutTests {
    /// Bench's first set, up, and the moment.
    static var onFirstSet: (LiveWorkout, Date) {
        WatchFixture.set.live
    }

    static func state(_ live: LiveWorkout, rev: Int, watchSeq: Int = 0) -> LinkState {
        LinkState(rev: rev, watchSeq: watchSeq, plan: live.workout, session: live.workoutSession)
    }

    @Test("A log applied twice logs once")
    func logTwice() throws {
        let (live, now) = Self.onFirstSet
        let set = try #require(live.currentSet)
        let once = try #require(live.applying(.log(set), at: now))
        let twice = LiveWorkout(workout: live.workout, workoutSession: once).applying(
            .log(set),
            at: now + 1,
        )
        #expect(once.sets.count == 1)
        #expect(twice == once)
    }

    @Test("Pause and resume are two actions, so one heard twice changes nothing more")
    func pauseTwice() throws {
        let (live, now) = Self.onFirstSet
        let paused = try #require(live.applying(.pause, at: now))
        let again = LiveWorkout(workout: live.workout, workoutSession: paused).applying(
            .pause,
            at: now + 3,
        )
        #expect(paused.isPaused)
        #expect(again == paused)
    }

    @Test("Of two counts begun for one set, the earlier wins, whichever is heard first")
    func earliestCountWins() throws {
        let (live, now) = WatchFixture.startIn.live
        var none = live
        none.workoutSession.count = nil
        let set = try #require(live.currentSet)
        let early = SetCount(set: set, startClock: 4)
        let late = SetCount(set: set, startClock: 6)
        let one = try #require(none.applying(.beginCount(early), at: now))
        let oneThenTwo = LiveWorkout(workout: live.workout, workoutSession: one)
            .applying(.beginCount(late), at: now)
        let two = try #require(none.applying(.beginCount(late), at: now))
        let twoThenOne = LiveWorkout(workout: live.workout, workoutSession: two)
            .applying(.beginCount(early), at: now)
        #expect(oneThenTwo?.count == early)
        #expect(twoThenOne?.count == early)
    }

    @Test("A rest's next change is its leaving; a set of reps has none; paused has none")
    func nextChange() throws {
        let (resting, at) = WatchFixture.resting.live
        let rest = try #require(resting.rest())
        #expect(resting.nextChange(after: at) == resting.workoutSession
            .date(ofClock: rest.leaveClock))
        let (set, setAt) = WatchFixture.set.live
        #expect(set.nextChange(after: setAt) == nil)
        let (paused, pausedAt) = WatchFixture.paused.live
        #expect(paused.nextChange(after: pausedAt) == nil)
    }

    @Test("A tap shows at once, stays through a state sent before it, and goes once confirmed")
    func tapSurvivesAnOlderState() throws {
        let (live, now) = Self.onFirstSet
        let session = live.workoutSession.id
        var linked = LinkedWorkout()
        linked.take(Self.state(live, rev: 1), for: session)
        let set = try #require(live.currentSet)
        linked.act(.log(set), at: now)
        #expect(linked.live?.workoutSession.sets.count == 1)

        linked.take(Self.state(live, rev: 2, watchSeq: 0), for: session)
        #expect(linked.live?.workoutSession.sets.count == 1)
        #expect(linked.pending.count == 1)

        let logged = try #require(live.applying(.log(set), at: now))
        let confirmed = LiveWorkout(workout: live.workout, workoutSession: logged)
        linked.take(Self.state(confirmed, rev: 3, watchSeq: 1), for: session)
        #expect(linked.pending.isEmpty)
        #expect(linked.live?.workoutSession.sets.count == 1)
    }

    @Test("A state older than the one held changes nothing")
    func olderStateIgnored() throws {
        let (live, now) = Self.onFirstSet
        let set = try #require(live.currentSet)
        let logged = try #require(live.applying(.log(set), at: now))
        var linked = LinkedWorkout()
        let session = live.workoutSession.id
        linked.take(
            Self.state(LiveWorkout(workout: live.workout, workoutSession: logged), rev: 5),
            for: session,
        )
        linked.take(Self.state(live, rev: 4), for: session)
        #expect(linked.live?.workoutSession.sets.count == 1)
    }

    @Test("A message goes through JSON and back whole, plan, session, and actions")
    func roundTrip() throws {
        let (live, now) = WatchFixture.perSide.live
        let state = Self.state(live, rev: 7, watchSeq: 3)
        let message = LinkMessage(session: live.workoutSession.id, body: .state(state))
        let back = try #require(LinkMessage.decoded(from: message.encoded()))
        #expect(back == message)
        guard case let .state(decoded) = back.body, let plan = decoded.plan else {
            Issue.record("Expected a state with its plan")
            return
        }
        let rebuilt = LiveWorkout(workout: plan.workout, workoutSession: decoded.session.session)
        #expect(rebuilt.watchFace(at: now) == live.watchFace(at: now))
        #expect(rebuilt.workoutSession == live.workoutSession)

        let set = try #require(live.currentSet)
        let actions = LinkMessage(session: live.workoutSession.id, body: .actions([
            LinkAction(seq: 1, at: now, action: .log(set)),
            LinkAction(seq: 2, at: now, action: .extendRest(by: 15)),
        ]))
        #expect(try LinkMessage.decoded(from: actions.encoded()) == actions)
    }

    @Test("A message of another wire version is dropped")
    func otherVersion() throws {
        var message = LinkMessage(session: UUID(), body: .hello)
        message.wire = LinkMessage.version + 1
        #expect(try LinkMessage.decoded(from: message.encoded()) == nil)
    }

    @Test("The Watch's copy survives a relaunch, its taps with it")
    func savedWhole() throws {
        let (live, now) = Self.onFirstSet
        var linked = LinkedWorkout()
        linked.take(Self.state(live, rev: 1), for: live.workoutSession.id)
        try linked.act(.log(#require(live.currentSet)), at: now)
        let back = try JSONDecoder().decode(LinkedWorkout.self, from: JSONEncoder().encode(linked))
        #expect(back == linked)
        #expect(back.live?.workoutSession.sets.count == 1)
    }
}
