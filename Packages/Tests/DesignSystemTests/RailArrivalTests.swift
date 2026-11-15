import Testing
@testable import DesignSystem

/// An added row's beats onto its rail, which no animation's completion or scroll that never
/// stops can hold back.
@Suite("Rail arrival")
struct RailArrivalTests {
    /// What `play` did, in order.
    private final class Steps {
        var done: [String] = []
    }

    /// Never returns until cancelled, as the wait for a scroll that never reports stopping.
    private static func never() async {
        try? await Task.sleep(for: .seconds(3600))
    }

    /// Without the give-up, `play` would wait out `never()` and the time limit fails the test.
    @Test(
        "A wait for the list's end that never ends still lets the row enter",
        .timeLimit(.minutes(1)),
    )
    func endNeverReached() async {
        let steps = Steps()
        await RailArrival.play(givingUpAfter: .milliseconds(50)) {
            true
        } reachEnd: {
            await Self.never()
        } enter: {
            steps.done.append("enter")
        } entered: {
            steps.done.append("entered")
        }
        #expect(steps.done == ["enter", "entered"])
    }

    @Test("A row a later add took the place of does not enter")
    func laterAddTakesOver() async {
        let steps = Steps()
        await RailArrival.play {
            false
        } reachEnd: {
            steps.done.append("reachEnd")
        } enter: {
            steps.done.append("enter")
        } entered: {
            steps.done.append("entered")
        }
        #expect(steps.done.isEmpty)
    }
}
