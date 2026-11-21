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
        let paused = KeyFill(length: 90, ends: .distantPast, pausedLeft: 60, isPaused: true)
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
}
