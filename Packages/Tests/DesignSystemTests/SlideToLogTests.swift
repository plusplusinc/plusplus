import CoreGraphics
import Testing
@testable import DesignSystem

/// The slide's arithmetic, from plain numbers: how far a drag takes the key, where it logs,
/// where a key let go coasts to, and how long it glides to the end; and the words the progress
/// line rolls by.
@Suite("Slide to log, its track")
@MainActor
struct SlideToLogTests {
    @Test("A drag moves the key along the track's travel, held within it")
    func progress() {
        let travel = SlideTrack.travel(track: 308, key: 64, inset: 4)
        #expect(travel == 236)
        #expect(SlideTrack.progress(translation: 118, travel: travel) == 0.5)
        #expect(SlideTrack.progress(translation: -20, travel: travel) == 0)
        #expect(SlideTrack.progress(translation: 400, travel: travel) == 1)
        #expect(SlideTrack.progress(translation: 50, travel: 0) == 0)
    }

    @Test("It logs from two-thirds of the way")
    func commit() {
        #expect(!SlideTrack.isArmed(0.66))
        #expect(SlideTrack.isArmed(2.0 / 3))
        #expect(SlideTrack.isArmed(1))
    }

    @Test("A quick flick from a quarter coasts past the commit; a slow drag stops short")
    func coast() {
        // 750 pt/s across a 236 pt travel, in tracks a second.
        #expect(SlideTrack.isArmed(SlideTrack.coast(from: 0.25, speed: 750.0 / 236)))
        #expect(!SlideTrack.isArmed(SlideTrack.coast(from: 0.25, speed: 200.0 / 236)))
        // Standing still, it stays where it was let go.
        #expect(SlideTrack.coast(from: 0.4, speed: 0) == 0.4)
    }

    @Test("Let go, the key glides to the end at the speed it was let go at, and slowest at the floor")
    func glide() {
        // At 2 tracks a second, from a quarter of the way: three quarters in 0.375 s.
        #expect(SlideTrack.glide(from: 0.25, speed: 2) == 0.375)
        // As fast from nearer the end: half the way, half the time.
        #expect(SlideTrack.glide(from: 0.625, speed: 2) == 0.1875)
        // Let go standing still, or backward, it crawls on at the floor.
        let crawl = Double(0.25 / SlideTrack.glideFloor)
        #expect(SlideTrack.glide(from: 0.75, speed: 0) == crawl)
        #expect(SlideTrack.glide(from: 0.75, speed: -1) == crawl)
        #expect(SlideTrack.glide(from: 1, speed: 2) == 0)
    }

    @Test("The progress line splits into words that keep their spaces, none empty")
    func words() {
        #expect(rollingWords("Set 2 of 3") == ["Set ", "2 ", "of ", "3"])
        // Joined, they are the line again, so a change rolls only the words that differ.
        #expect(rollingWords("Set 2 of 3").joined() == "Set 2 of 3")
        let side = "\u{00A0}·\u{00A0}Left"
        #expect(rollingWords(side) == ["\u{00A0}", "·\u{00A0}", "Left"])
        // A line ending in a space ends on its last word, not on an empty one.
        #expect(rollingWords("Set 2 ") == ["Set ", "2 "])
        #expect(rollingWords("").isEmpty)
    }
}
