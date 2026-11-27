import Foundation
import Testing
@testable import DesignSystem

/// How far a count's key has filled at a moment, and what VoiceOver hears of it: a rest's
/// "Skip rest" and a timed set's "Log early" alike.
struct KeyFillTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 1000)
    private static let locale = Locale(identifier: "en_US")

    /// A fill `length` seconds long that ends `left` seconds after `now`.
    private static func running(_ length: Double, left: Double) -> KeyFill {
        KeyFill(length: length, ends: now.addingTimeInterval(left))
    }

    @Test("A fill is empty at its start, grows with each second, is full at its end and no further")
    func shareRuns() {
        let fill = Self.running(30, left: 30)
        let shares = [0, 10, 20, 30, 45].map { fill.share(at: Self.now.addingTimeInterval($0)) }
        #expect(shares[0] == 0)
        #expect(shares[1] < shares[2])
        #expect(shares[3] == 1)
        #expect(shares[4] == 1)
    }

    @Test("+15 s steps the fill back: at the same moment, less is filled")
    func extendSteps() {
        let before = Self.running(30, left: 12)
        let after = Self.running(45, left: 27)
        #expect(after.share(at: Self.now) < before.share(at: Self.now))
    }

    @Test("A paused fill holds its share at any moment; one over is full")
    func pausedHolds() {
        let paused = KeyFill(length: 90, ends: .distantPast, pausedLeft: 60)
        #expect(paused.share(at: Self.now) == paused.share(at: Self.now.addingTimeInterval(500)))
        #expect(abs(paused.share(at: Self.now) - 1.0 / 3) < 1e-9)
        #expect(KeyFill(length: 90, ends: .distantFuture, isOver: true).share(at: Self.now) == 1)
    }

    @Test("Skip rest's value is the time left, rounded up as the count shows it; none once over")
    func spokenLeft() {
        #expect(Self.running(90, left: 35).spokenLeft(at: Self.now, locale: Self.locale)
            == "35 seconds left")
        #expect(Self.running(90, left: 64.2).spokenLeft(at: Self.now, locale: Self.locale)
            == "1 minute, 5 seconds left")
        #expect(KeyFill.over.spokenLeft(at: Self.now, locale: Self.locale) == nil)
    }

    @Test(
        "A fill redraws as its edge moves a pixel: a long rest's less often, none past 60 a second",
    )
    func redrawsByThePixel() {
        // Skip rest's face on a phone, at 3 pixels a point.
        let (width, scale): (CGFloat, CGFloat) = (280, 3)
        let pixel = 1 / (width * scale)
        for length in [5.0, 30, 90, 300] {
            let fill = Self.running(length, left: length)
            let interval = fill.redrawInterval(width: width, scale: scale)
            let moved = fill.share(at: Self.now.addingTimeInterval(interval))
                - fill.share(at: Self.now)
            #expect(interval >= 1.0 / 60, "\(length) s redraws past 60 a second")
            // A pixel a redraw, or every frame at 60 a second, where a short count moves further.
            #expect(
                interval == 1.0 / 60 || abs(moved - pixel) < 1e-9,
                "\(length) s moves \(moved / pixel) px a redraw",
            )
        }
        let short = Self.running(5, left: 5).redrawInterval(width: width, scale: scale)
        let long = Self.running(300, left: 300).redrawInterval(width: width, scale: scale)
        #expect(long > short * 10, "A long rest redraws as often as a short one")
    }
}
