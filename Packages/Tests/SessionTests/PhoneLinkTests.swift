import Foundation
import Health
import Synchronization
import Testing
@testable import Session
@testable import WorkoutStore

/// The phone's side of the link, against a fake mirrored session: what it sends the Watch, and
/// what it does with the Watch's actions.
@MainActor
@Suite("Phone link")
struct PhoneLinkTests {
    /// What the fake was asked, and a way to play the Watch's side.
    final class FakeMirror: Sendable {
        let sent = Mutex<[LinkMessage]>([])
        let opened = Mutex(0)
        let events: AsyncStream<MirrorEvent>
        let watch: AsyncStream<MirrorEvent>.Continuation

        init() {
            (events, watch) = AsyncStream.makeStream(of: MirrorEvent.self)
        }

        var mirror: WorkoutMirror {
            WorkoutMirror(
                events: events,
                openWatchApp: { self.opened.withLock { $0 += 1 } },
                send: { data in
                    if let message = LinkMessage.decoded(from: data) {
                        self.sent.withLock { $0.append(message) }
                    }
                },
            )
        }

        func states() -> [LinkState] {
            sent.withLock { $0 }.compactMap {
                if case let .state(state) = $0.body {
                    state
                } else {
                    nil
                }
            }
        }
    }

    /// Waits up to two seconds for `condition`.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        let start = ContinuousClock.now
        while !condition() {
            guard ContinuousClock.now - start < .seconds(2) else { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    @Test("Start brings up the Watch app once; a handed-over session hears hello, then the workout")
    func startAndConnect() async throws {
        let workout = WatchFixture.benchWorkout
        let session = AppSession(workout: workout, store: nil, namer: .muscleGroupsOnly)
        let fake = FakeMirror()
        let link = PhoneLink(session: session, mirror: fake.mirror)
        session.start(on: workout.id, at: .now)
        #expect(await eventually { fake.opened.withLock { $0 } == 1 })

        fake.watch.yield(.connected)
        #expect(await eventually { fake.sent.withLock { $0 }.contains { $0.body == .hello } })
        let id = try #require(session.workoutSession?.id)
        let hello = try LinkMessage(session: id, body: .hello).encoded()
        fake.watch.yield(.received(hello))
        #expect(await eventually { fake.states().last?.plan != nil })
        #expect(fake.opened.withLock { $0 } == 1)
        _ = link
    }

    @Test("The Watch's actions are applied once each, however often they come")
    func actionsOnce() async throws {
        let workout = WatchFixture.benchWorkout
        let session = AppSession(workout: workout, store: nil, namer: .muscleGroupsOnly)
        let fake = FakeMirror()
        let link = PhoneLink(session: session, mirror: fake.mirror)
        let start = Date.now.addingTimeInterval(-30)
        session.start(on: workout.id, at: start)
        session.landOnFirstSet(at: start)
        fake.watch.yield(.connected)
        let running = try #require(session.workoutSession)
        let set = try #require(LiveWorkout(workout: workout, workoutSession: running).currentSet)
        let actions = LinkMessage(session: running.id, body: .actions([
            LinkAction(seq: 1, at: .now, action: .log(set)),
            LinkAction(seq: 2, at: .now, action: .extendRest(by: 15)),
        ]))
        let data = try actions.encoded()
        fake.watch.yield(.received(data))
        fake.watch.yield(.received(data))
        #expect(await eventually { fake.states().last?.watchSeq == 2 })
        let logged = try #require(session.workoutSession)
        #expect(logged.sets.count == 1)
        #expect(logged.sets.first?.restAdjustment == 15)
        _ = link
    }

    @Test("A message for a workout the phone is not running is answered with its end")
    func unknownSession() async throws {
        let session = AppSession(
            workout: WatchFixture.benchWorkout,
            store: nil,
            namer: .muscleGroupsOnly,
        )
        let fake = FakeMirror()
        let link = PhoneLink(session: session, mirror: fake.mirror)
        let stray = UUID()
        try fake.watch.yield(.received(LinkMessage(session: stray, body: .hello).encoded()))
        #expect(await eventually {
            fake.sent.withLock { $0 }.contains {
                if case .ended = $0.body {
                    $0.session == stray
                } else {
                    false
                }
            }
        })
        _ = link
    }
}
