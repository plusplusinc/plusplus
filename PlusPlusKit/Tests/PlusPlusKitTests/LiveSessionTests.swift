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

    func started(origin: Origin = .phone, at offset: TimeInterval = 0, steps: [WatchSync.Step], routineUuid: UUID? = nil) -> Op {
        Op(opId: UUID(), sessionId: session, origin: origin, seq: 0, at: t0.addingTimeInterval(offset),
           kind: .started(routineName: "Push Day", startedAt: t0.addingTimeInterval(offset), restSeconds: 90, steps: steps, routineUuid: routineUuid))
    }

    func logSet(_ index: Int, reps: Int, origin: Origin = .phone, seq: Int, at offset: TimeInterval, opId: UUID = UUID()) -> Op {
        Op(opId: opId, sessionId: session, origin: origin, seq: seq, at: t0.addingTimeInterval(offset),
           kind: .logSet(index: index, actualWeight: nil, actualReps: reps, actualDuration: nil, extras: [:], completedAt: t0.addingTimeInterval(offset)))
    }

    // MARK: Pause, steps, and cross-session buffering (stage 3, #512)

    @Test("Pause and resume fold LWW like every other register")
    func pauseResumeLWW() throws {
        let pauseAt = t0.addingTimeInterval(30)
        var s = try #require(LiveSession.reduce([
            started(steps: steps(["Bench"])),
            Op(opId: UUID(), sessionId: session, origin: .phone, seq: 1,
               at: pauseAt, kind: .paused(at: pauseAt)),
        ]))
        #expect(s.isPaused)
        // A stale duplicate of the pause cannot un-resume.
        let resumeAt = t0.addingTimeInterval(60)
        s.apply(Op(opId: UUID(), sessionId: session, origin: .phone, seq: 2,
                   at: resumeAt, kind: .resumed(at: resumeAt)))
        #expect(!s.isPaused)
        s.apply(Op(opId: UUID(), sessionId: session, origin: .phone, seq: 1,
                   at: pauseAt, kind: .paused(at: pauseAt)))
        #expect(!s.isPaused)
        // The pause registers count as activity: displacement's guard
        // reads latestStamp, and a register it misses is a window for a
        // stale foreign birth (stage-3 review).
        #expect(s.latestStamp == s.pauseStamp)
    }

    @Test("A steps change replaces the birth list and survives merge")
    func stepsChangedReplaces() throws {
        var s = try #require(LiveSession.reduce([started(steps: steps(["Bench", "Row"]))]))
        let grown = steps(["Bench", "Row", "Squat"])
        s.apply(Op(opId: UUID(), sessionId: session, origin: .phone, seq: 1,
                   at: t0.addingTimeInterval(120), kind: .stepsChanged(steps: grown)))
        #expect(s.totalSteps == 3)
        // A peer still holding the birth list merges to the changed one.
        var peer = try #require(LiveSession.reduce([started(steps: steps(["Bench", "Row"]))]))
        peer.merge(s)
        #expect(peer.totalSteps == 3)
    }

    @Test("A foreign session's ops buffer across displacement instead of dropping")
    func crossSessionBuffering() {
        var reducer = LiveSession.Reducer()
        reducer.apply(started(steps: steps(["Bench"])))
        // A NEW session's log arrives BEFORE its queued birth (the
        // reachability flip): held, not dropped.
        let other = UUID()
        let lateLog = Op(opId: UUID(), sessionId: other, origin: .watch, seq: 1,
                         at: t0.addingTimeInterval(3700),
                         kind: .logSet(index: 0, actualWeight: nil, actualReps: 7,
                                       actualDuration: nil, extras: [:],
                                       completedAt: t0.addingTimeInterval(3700)))
        reducer.apply(lateLog)
        let birth = Op(opId: UUID(), sessionId: other, origin: .watch, seq: 0,
                       at: t0.addingTimeInterval(3600),
                       kind: .started(routineName: "Legs", startedAt: t0.addingTimeInterval(3600),
                                      restSeconds: 60, steps: steps(["Squat"]), routineUuid: nil))
        reducer.apply(birth)
        #expect(reducer.state?.sessionId == other)
        #expect(reducer.state?.log(at: 0)?.actualReps == 7)
    }

    @Test("An op with an unknown kind fails to decode, so ingest drops just that op")
    func unknownKindDecodeThrows() {
        // A FUTURE peer's op kind: the documented degrade is that the
        // whole op is dropped by the ingest sites' try?, nothing more.
        let json = """
        {"at":"2026-07-30T12:00:00Z","kind":{"teleported":{}},"opId":"\(UUID().uuidString)","origin":"watch","seq":1,"sessionId":"\(UUID().uuidString)"}
        """
        #expect(throws: (any Error).self) {
            _ = try WatchSync.decode(Op.self, from: Data(json.utf8))
        }
    }

    // MARK: Identity fields (stage 2 of the watch repair, #511)

    @Test("A started op from a build without routineUuid still decodes")
    func oldStartedOpDecodes() throws {
        // Hand-written pre-#511 wire format: no routineUuid key.
        let json = """
        {"at":"2026-07-30T12:00:00Z","kind":{"started":{"restSeconds":90,"routineName":"Push Day","startedAt":"2026-07-30T12:00:00Z","steps":[]}},"opId":"\(UUID().uuidString)","origin":"watch","seq":0,"sessionId":"\(UUID().uuidString)"}
        """
        let op = try WatchSync.decode(Op.self, from: Data(json.utf8))
        guard case let .started(name, _, _, _, uuid) = op.kind else {
            Issue.record("decoded op is not .started")
            return
        }
        #expect(name == "Push Day")
        #expect(uuid == nil)
    }

    @Test("A result and a plan routine from older builds decode with nil identity")
    func oldResultAndPlanDecode() throws {
        let result = """
        {"endedAt":"2026-07-30T13:00:00Z","restSeconds":90,"routineName":"Push Day","startedAt":"2026-07-30T12:00:00Z","steps":[]}
        """
        let decoded = try WatchSync.decode(WatchSync.SessionResult.self, from: Data(result.utf8))
        #expect(decoded.sessionId == nil)
        let plan = """
        {"name":"Push Day","restSeconds":90,"steps":[]}
        """
        let routine = try WatchSync.decode(WatchSync.PlanRoutine.self, from: Data(plan.utf8))
        #expect(routine.uuid == nil)
        #expect(routine.isQuickStart == nil)
    }

    @Test("The identity fields survive the codec round-trip")
    func identityRoundTrip() throws {
        let rid = UUID()
        let sid = UUID()
        let op = Op(opId: UUID(), sessionId: sid, origin: .phone, seq: 0, at: t0,
                    kind: .started(routineName: "Push Day", startedAt: t0, restSeconds: 90,
                                   steps: [], routineUuid: rid))
        let back = try WatchSync.decode(Op.self, from: WatchSync.encode(op))
        #expect(back == op)
        let result = WatchSync.SessionResult(routineName: "Push Day", startedAt: t0, endedAt: t0,
                                             restSeconds: 90, steps: [], sessionId: sid)
        let resultBack = try WatchSync.decode(WatchSync.SessionResult.self, from: WatchSync.encode(result))
        #expect(resultBack.sessionId == sid)
    }

    // MARK: Displacement (stage 1 of the watch repair, #510)

    @Test("A newer started for a different session displaces a stale unfinished state")
    func newerStartDisplaces() {
        var reducer = LiveSession.Reducer()
        reducer.apply(started(steps: steps(["Bench", "Row"])))
        reducer.apply(logSet(0, reps: 5, seq: 1, at: 10))
        // The first session's discard was lost; a new session begins an
        // hour later. One human: the new start means the old one is over.
        let other = UUID()
        let fresh = Op(
            opId: UUID(), sessionId: other, origin: .phone, seq: 0,
            at: t0.addingTimeInterval(3600),
            kind: .started(routineName: "Legs", startedAt: t0.addingTimeInterval(3600),
                           restSeconds: 60, steps: steps(["Squat"]), routineUuid: nil)
        )
        reducer.apply(fresh)
        #expect(reducer.state?.sessionId == other)
        #expect(reducer.state?.routineName == "Legs")
    }

    @Test("A replayed older started for a previous session cannot clobber the live one")
    func olderStartRefused() {
        var reducer = LiveSession.Reducer()
        reducer.apply(started(steps: steps(["Bench"])))
        reducer.apply(logSet(0, reps: 5, seq: 1, at: 10))
        // A duplicate delivery of yesterday's birth arrives late.
        let old = Op(
            opId: UUID(), sessionId: UUID(), origin: .watch, seq: 0,
            at: t0.addingTimeInterval(-3600),
            kind: .started(routineName: "Yesterday", startedAt: t0.addingTimeInterval(-3600),
                           restSeconds: 60, steps: steps(["Row"]), routineUuid: nil)
        )
        reducer.apply(old)
        #expect(reducer.state?.routineName == "Push Day")
    }

    @Test("A discarded state reads closed without reading finished")
    func discardedIsClosed() throws {
        var s = try #require(LiveSession.reduce([started(steps: steps(["Bench"]))]))
        #expect(!s.isClosed)
        s.apply(Op(opId: UUID(), sessionId: session, origin: .phone, seq: 1,
                   at: t0.addingTimeInterval(5), kind: .discarded))
        #expect(s.isClosed)
        #expect(!s.isFinished)
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
