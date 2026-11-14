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

    @Test("Cancelled, the wait ends")
    func cancelEnds() async {
        let beat = ScrollBeat()
        let task = await wait(on: beat, giveUp: Self.never)
        task.cancel()
        await task.value
    }
}
