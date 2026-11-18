import SwiftUI
import Testing
@testable import DesignSystem

/// A sequence's wait for a scroll to stop, which a scroll that never reports stopping does not
/// hold forever.
@Suite("Scroll beat")
struct ScrollBeatTests {
    /// Starts waiting on `beat`, giving up when `giveUp` returns, and returns once the scroll has
    /// been asked for, with the task waiting.
    private func wait(
        on beat: ScrollBeat,
        giveUp: @escaping @MainActor () async -> Void,
    ) async -> Task<Void, Never> {
        var scrolled = false
        let task = Task { await beat.settled(after: { scrolled = true }, orWhen: giveUp) }
        while !scrolled {
            await Task.yield()
        }
        return task
    }

    /// Never gives up until cancelled.
    private static func never() async {
        try? await Task.sleep(for: .seconds(3600))
    }

    @Test("The list reporting it has stopped ends the wait")
    func idleEnds() async {
        let beat = ScrollBeat()
        let task = await wait(on: beat, giveUp: Self.never)
        beat.phaseChanged(to: .animating)
        beat.phaseChanged(to: .idle)
        await task.value
    }

    @Test("With no stop reported, the wait ends when it gives up")
    func giveUpEnds() async {
        let beat = ScrollBeat()
        let (gate, open) = AsyncStream<Void>.makeStream()
        var stoppedEarly = true
        let task = await wait(on: beat) {
            for await _ in gate { }
            // Cancelled if anything ended the wait before it gave up.
            stoppedEarly = Task.isCancelled
        }
        beat.phaseChanged(to: .animating)
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        open.finish()
        await task.value
        #expect(!stoppedEarly, "A scroll still moving does not end the wait")
    }

    @Test("A wait that ended does not end the next one when its give-up returns late")
    @MainActor
    func endedWaitLeavesNextAlone() async {
        let beat = ScrollBeat()
        let gate = Gate()
        let first = await wait(on: beat) { await gate.wait() }
        beat.phaseChanged(to: .idle)
        await first.value
        var ended = false
        var scrolled = false
        let second = Task {
            await beat.settled(after: { scrolled = true }, orWhen: Self.never)
            ended = true
        }
        while !scrolled {
            await Task.yield()
        }
        // The first wait's give-up, cancelled when it ended, returns only now.
        gate.open()
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        #expect(!ended)
        second.cancel()
        await second.value
    }

    /// A give-up that returns only when opened, cancelled or not.
    @MainActor
    private final class Gate {
        private var opened: CheckedContinuation<Void, Never>?

        func wait() async {
            await withCheckedContinuation { opened = $0 }
        }

        func open() {
            opened?.resume()
            opened = nil
        }
    }

    @Test("Cancelled, the wait ends")
    func cancelEnds() async {
        let beat = ScrollBeat()
        let task = await wait(on: beat, giveUp: Self.never)
        task.cancel()
        await task.value
    }

    /// The order a slow machine met after Start: a landing asked for, and the row's next place in
    /// before the list
    /// reports the scroll. Read from the report alone, the list was elsewhere, so nothing landed
    /// it again.
    @Test("A landing asked for and not yet reported counts as resting there")
    func landingAskedRests() {
        let beat = ScrollBeat()
        beat.listMoved(to: 0)
        var position = ScrollPosition()
        position.scrollTo(y: 871)
        #expect(beat.rests(on: 871, asked: position))
        #expect(!beat.rests(on: 813, asked: position))
    }

    @Test("Scrolled to an edge, the list rests only where it reports")
    func edgeFallsBackToReport() {
        let beat = ScrollBeat()
        beat.listMoved(to: 240)
        var position = ScrollPosition()
        position.scrollTo(edge: .top)
        #expect(beat.rests(on: 240, asked: position))
        #expect(!beat.rests(on: 0, asked: position))
    }
}
