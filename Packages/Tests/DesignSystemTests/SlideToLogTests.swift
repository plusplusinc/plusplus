import CoreGraphics
import Testing
@testable import DesignSystem

/// The slide's arithmetic, from plain numbers: how far a drag takes the key, where it logs, and
/// where a key let go coasts to, and when it crosses the commit on the way.
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

    @Test("Coasting to the end, it crosses the commit inside the coast, sooner from nearer it")
    func coastTiming() {
        let far = SlideTrack.coastTiming(from: 0.25, speed: 4)
        let near = SlideTrack.coastTiming(from: 0.6, speed: 4)
        for timing in [far, near] {
            #expect(timing.duration >= 0.12 && timing.duration <= 0.4)
            #expect(timing.crossing > 0 && timing.crossing < timing.duration)
        }
        #expect(near.crossing < far.crossing)
        // From past the commit, it has crossed already.
        #expect(SlideTrack.coastTiming(from: 0.8, speed: 4).crossing == 0)
    }
}
