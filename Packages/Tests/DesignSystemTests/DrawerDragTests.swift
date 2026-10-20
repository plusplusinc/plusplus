import CoreGraphics
import Testing
@testable import DesignSystem

/// How far a swipe holds the drawer open and where it settles, from plain numbers.
@Suite("Drawer drag")
struct DrawerDragTests {
    private let width: CGFloat = 300

    @Test("The drawer follows the finger from closed and from open, never past either end")
    func progress() {
        #expect(DrawerDrag.progress(translation: 75, width: width, from: 0) == 0.25)
        #expect(DrawerDrag.progress(translation: -75, width: width, from: 1) == 0.75)
        #expect(DrawerDrag.progress(translation: -40, width: width, from: 0) == 0)
        #expect(DrawerDrag.progress(translation: 500, width: width, from: 0) == 1)
        #expect(DrawerDrag.progress(translation: 40, width: width, from: 1) == 1)
    }

    @Test("A slow release settles on whichever side of halfway it is")
    func halfway() {
        #expect(DrawerDrag.settlesOpen(progress: 0.6, velocity: 0))
        #expect(!DrawerDrag.settlesOpen(progress: 0.4, velocity: 0))
        #expect(DrawerDrag.settlesOpen(progress: 0.6, velocity: -100))
        #expect(!DrawerDrag.settlesOpen(progress: 0.4, velocity: 100))
    }

    @Test("A flick settles the way it goes, wherever it is let go")
    func flick() {
        let flick = DrawerDrag.flickSpeed
        #expect(DrawerDrag.settlesOpen(progress: 0.1, velocity: flick))
        #expect(!DrawerDrag.settlesOpen(progress: 0.9, velocity: -flick))
    }

    @Test("With Reduce Motion, a short swipe the right way opens or closes it")
    func reducedMotion() {
        let reach = DrawerDrag.reducedMotionReach
        #expect(DrawerDrag.swipeOpens(translation: reach, fromOpen: false))
        #expect(!DrawerDrag.swipeOpens(translation: reach - 1, fromOpen: false))
        #expect(!DrawerDrag.swipeOpens(translation: -reach, fromOpen: true))
        #expect(DrawerDrag.swipeOpens(translation: -(reach - 1), fromOpen: true))
    }

    @Test("Let go, the drawer leaves at the finger's speed, never backward")
    func releaseSpeed() {
        // Half open and opening at 300 pt/s: 150 pt to go, so two lengths a second.
        #expect(DrawerDrag.releaseSpeed(
            velocity: 300, progress: 0.5, opens: true, width: width,
        ) == 2)
        #expect(DrawerDrag.releaseSpeed(
            velocity: 300, progress: 0.5, opens: false, width: width,
        ) == 0)
        #expect(DrawerDrag.releaseSpeed(
            velocity: -5000, progress: 0.999, opens: false, width: width,
        ) <= 20)
        #expect(DrawerDrag.releaseSpeed(
            velocity: 300, progress: 1, opens: true, width: width,
        ) == 0)
    }
}
