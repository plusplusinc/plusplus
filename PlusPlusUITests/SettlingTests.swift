import XCTest

/// `settling`, the loop behind `settles()`, over made-up frames and a made-up clock, so a slow
/// accessibility query is a number and no app launches.
///
/// `nonisolated` because XCTestCase's initializers are; `settling` runs on the main actor.
final nonisolated class SettlingTests: XCTestCase {
    /// On a slow runner the first frame read took 5.3 s, past a 2 s timeout counted from the
    /// call, and the wait gave up with no second read to compare (GitHub run 40232167147).
    @MainActor
    func testSettlesAfterAFirstReadSlowerThanTheTimeout() {
        var time = Date(timeIntervalSinceReferenceDate: 0)
        var reads = 0
        func read() -> CGRect {
            reads += 1
            time += reads == 1 ? 5 : 0.125
            return CGRect(x: 0, y: 100, width: 50, height: 44)
        }
        XCTAssertTrue(
            settling(read(), still: 0.25, within: 2, now: { time }),
            "A still frame read as moving after one slow read",
        )
    }

    @MainActor
    func testKeepsMovingWhileTheFrameChanges() {
        var time = Date(timeIntervalSinceReferenceDate: 0)
        var reads = 0
        func read() -> CGRect {
            reads += 1
            time += 0.125
            return CGRect(x: 0, y: CGFloat(reads), width: 50, height: 44)
        }
        XCTAssertFalse(
            settling(read(), still: 0.25, within: 2, now: { time }),
            "A frame that kept changing read as settled",
        )
        // Steps of 1/8 s add up exactly: the 17th read answers at the deadline, 2 s past the first.
        XCTAssertEqual(reads, 17, "It read on past the timeout, or stopped short of it")
    }
}
