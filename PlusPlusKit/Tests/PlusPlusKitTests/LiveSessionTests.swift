import Testing
import Foundation
@testable import PlusPlusKit

@Suite("Live session op reduction")
struct LiveSessionTests {
    typealias Op = LiveSession.Op
    typealias Origin = LiveSession.Origin

    // MARK: Builders

    let session = UUID()
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func steps(_ names: [String]) -> [WatchSync.Step] {
        names.enumerated().map { i, n in
            WatchSync.Step(exerciseName: n, groupIndex: 0, setNumber: i + 1, isDuration: false)
        }
    }

    func started(origin: Origin = .phone, at offset: TimeInterval = 0, steps: [WatchSync.Step]) -> Op {
        Op(opId: UUID(), sessionId: session, origin: origin, seq: 0, at: t0.addingTimeInterval(offset),
           kind: .started(routineName: "Push Day", startedAt: t0.addingTimeInterval(offset), restSeconds: 90, steps: steps))
    }

    func logSet(_ index: Int, reps: Int, origin: Origin = .phone, seq: Int, at offset: TimeInterval, opId: UUID = UUID()) -> Op {
        Op(opId: opId, sessionId: session, origin: origin, seq: seq, at: t0.addingTimeInterval(offset),
           kind: .logSet(index: index, actualWeight: nil, actualReps: reps, actualDuration: nil, extras: [:], completedAt: t0.addingTimeInterval(offset)))
    }

    // MARK: Basics

    @Test("Started plus two logs yields two completed and the cursor at the third")
    func basicReduction() throws {
        let s = try #require(LiveSession.reduce([
            started(steps: steps(["Bench", "Row", "Squat"])),
            logSet(0, reps: 5, seq: 1, at: 10),
            logSet(1, reps: 8, seq: 2, at: 20),
        ]))
        #expect(s.completedCount == 2)
        #expect(s.totalSteps == 3)
        #expect(s.currentIndex == 2)
        #expect(s.log(at: 1)?.actualReps == 8)
    }

    @Test("A repeated op is a no-op (idempotent by opId)")
    func idempotent() throws {
        let dupe = logSet(0, reps: 5, seq: 1, at: 10)
        let s = try #require(LiveSession.reduce([
            started(steps: steps(["Bench", "Row"])),
            dupe, dupe, dupe,
        ]))
        #expect(s.completedCount == 1)
        #expect(s.applied.count == 2) // started + one log
    }

    @Test("Reduction is independent of delivery order, including started arriving last")
    func orderIndependent() throws {
        let ops = [
            started(steps: steps(["Bench", "Row", "Squat"])),
            logSet(0, reps: 5, seq: 1, at: 10),
            logSet(1, reps: 8, seq: 2, at: 20),
            logSet(2, reps: 3, seq: 3, at: 30),
        ]
        let forward = try #require(LiveSession.reduce(ops))
        let reversed = try #require(LiveSession.reduce(ops.reversed()))
        #expect(forward == reversed)
        #expect(reversed.completedCount == 3)
    }

    // MARK: Conflict resolution

    @Test("Same slot, later stamp wins regardless of order")
    func lastWriterWins() throws {
        let early = logSet(0, reps: 5, seq: 1, at: 10)
        let late = logSet(0, reps: 12, seq: 2, at: 20)
        let a = try #require(LiveSession.reduce([started(steps: steps(["Bench"])), early, late]))
        let b = try #require(LiveSession.reduce([started(steps: steps(["Bench"])), late, early]))
        #expect(a.log(at: 0)?.actualReps == 12)
        #expect(b.log(at: 0)?.actualReps == 12)
    }

    @Test("On an equal instant, the phone beats the watch")
    func phoneWinsTie() throws {
        let watchLog = logSet(0, reps: 3, origin: .watch, seq: 7, at: 15)
        let phoneLog = logSet(0, reps: 10, origin: .phone, seq: 1, at: 15)
        let a = try #require(LiveSession.reduce([started(steps: steps(["Bench"])), watchLog, phoneLog]))
        let b = try #require(LiveSession.reduce([started(steps: steps(["Bench"])), phoneLog, watchLog]))
        #expect(a.log(at: 0)?.actualReps == 10)
        #expect(b.log(at: 0)?.actualReps == 10)
    }

    // MARK: Merge

    @Test("Merging two divergent states converges both ways")
    func mergeConverges() throws {
        let phone = try #require(LiveSession.reduce([
            started(steps: steps(["Bench", "Row"])),
            logSet(0, reps: 5, origin: .phone, seq: 1, at: 10),
        ]))
        var watch = try #require(LiveSession.reduce([
            started(steps: steps(["Bench", "Row"])),
            logSet(1, reps: 8, origin: .watch, seq: 1, at: 12),
        ]))
        // NB: both were born from DIFFERENT started ops → different
        // sessionIds. Force the same identity to model one shared session.
        watch.sessionId = phone.sessionId
        var ab = phone; ab.merge(watch)
        var ba = watch; ba.merge(phone)
        #expect(ab.completedCount == 2)
        #expect(ba.completedCount == 2)
        #expect(ab.log(at: 0)?.actualReps == 5)
        #expect(ab.log(at: 1)?.actualReps == 8)
    }

    @Test("Merge is idempotent")
    func mergeIdempotent() throws {
        let base = try #require(LiveSession.reduce([
            started(steps: steps(["Bench", "Row"])),
            logSet(0, reps: 5, seq: 1, at: 10),
        ]))
        var once = base; once.merge(base)
        #expect(once == base)
    }

    // MARK: Custody handoff (watch-born, phone adopts)

    @Test("A watch-born session is adopted by an empty phone reducer")
    func custodyHandoff() throws {
        let watchState = try #require(LiveSession.reduce([
            started(origin: .watch, steps: steps(["Run"])),
            logSet(0, reps: 1, origin: .watch, seq: 1, at: 30),
        ]))
        var phone = LiveSession.Reducer()
        phone.adopt(watchState)
        #expect(phone.state?.origin == .watch)
        #expect(phone.state?.completedCount == 1)
        #expect(phone.state?.sessionId == watchState.sessionId)
    }

    @Test("Ops buffered before started are replayed on adoption")
    func bufferedBeforeStarted() throws {
        var r = LiveSession.Reducer()
        let start = started(steps: steps(["Bench", "Row"]))
        // Log arrives before we ever see the started op.
        r.apply(logSet(1, reps: 8, seq: 2, at: 20))
        #expect(r.state == nil)
        r.apply(start)
        #expect(r.state?.completedCount == 1)
        #expect(r.state?.log(at: 1)?.actualReps == 8)
    }

    // MARK: Rest + lifecycle

    @Test("Rest start then a later rest-end clears rest, order-independent")
    func restLifecycle() throws {
        let start = started(steps: steps(["Bench", "Row"]))
        let restOn = Op(opId: UUID(), sessionId: session, origin: .phone, seq: 1, at: t0.addingTimeInterval(10), kind: .restStarted(endsAt: t0.addingTimeInterval(100), total: 90))
        let restOff = Op(opId: UUID(), sessionId: session, origin: .phone, seq: 2, at: t0.addingTimeInterval(40), kind: .restEnded)
        let a = try #require(LiveSession.reduce([start, restOn, restOff]))
        let b = try #require(LiveSession.reduce([start, restOff, restOn]))
        #expect(a.isResting == false)
        #expect(b.isResting == false)
    }

    @Test("Finished stamps an end date and marks the session finished")
    func finished() throws {
        let start = started(steps: steps(["Bench"]))
        let fin = Op(opId: UUID(), sessionId: session, origin: .phone, seq: 5, at: t0.addingTimeInterval(300), kind: .finished(endedAt: t0.addingTimeInterval(300)))
        let s = try #require(LiveSession.reduce([start, fin, logSet(0, reps: 5, seq: 1, at: 10)]))
        #expect(s.isFinished)
        #expect(s.endedAt == t0.addingTimeInterval(300))
        #expect(s.completedCount == 1) // a late log still lands in its own field
    }

    @Test("Discarded is recorded and beats an earlier finish")
    func discarded() throws {
        let start = started(steps: steps(["Bench"]))
        let fin = Op(opId: UUID(), sessionId: session, origin: .phone, seq: 1, at: t0.addingTimeInterval(100), kind: .finished(endedAt: t0.addingTimeInterval(100)))
        let disc = Op(opId: UUID(), sessionId: session, origin: .phone, seq: 2, at: t0.addingTimeInterval(200), kind: .discarded)
        let s = try #require(LiveSession.reduce([start, fin, disc]))
        #expect(s.discarded)
    }

    // MARK: Codec

    @Test("State and Op survive the WatchSync codec round-trip")
    func codecRoundTrip() throws {
        let s = try #require(LiveSession.reduce([
            started(steps: steps(["Bench", "Row"])),
            logSet(0, reps: 5, seq: 1, at: 10),
        ]))
        let data = try WatchSync.encode(s)
        let back = try WatchSync.decode(LiveSession.State.self, from: data)
        #expect(back == s)

        let op = logSet(1, reps: 8, seq: 2, at: 20)
        let opData = try WatchSync.encode(op)
        let opBack = try WatchSync.decode(LiveSession.Op.self, from: opData)
        #expect(opBack == op)
    }
}
