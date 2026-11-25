import Testing
@testable import DesignSystem

/// How a bar's key swaps for another, from plain values.
@Suite("Key stage")
struct KeyStageTests {
    private struct Face: Equatable, Identifiable {
        let id: Int
        let words: String
    }

    private let log = Face(id: 1, words: "Log set")
    private let logRight = Face(id: 1, words: "Log right")
    private let back = Face(id: 2, words: "Bench press")
    private let finish = Face(id: 3, words: "Finish workout")

    @Test("Showing, the same key's new words draw at once and are followed in place")
    func withinAKind() {
        var stage = KeyStage.showing(log)
        #expect(stage.face(for: logRight) == logRight)
        let changed = stage.follow(to: logRight)
        #expect(!changed)
        #expect(stage == .showing(logRight))
    }

    @Test("Another key's face, not yet followed, draws the key as it was")
    func beforeFollowing() {
        let stage = KeyStage.showing(logRight)
        #expect(stage.face(for: finish) == logRight)
    }

    @Test("A change of kind starts the key leaving, drawing its own words whatever is live")
    func changeOfKind() {
        var stage = KeyStage.showing(logRight)
        let changed = stage.follow(to: finish)
        #expect(changed)
        #expect(stage == .leaving(logRight))
        #expect(stage.face(for: finish) == logRight)
        #expect(stage.face(for: back) == logRight)
    }

    @Test("While leaving or arriving, further changes change nothing")
    func whileOut() {
        var leaving = KeyStage.leaving(log)
        let leavingChanged = leaving.follow(to: back)
        #expect(!leavingChanged)
        #expect(leaving == .leaving(log))
        var arriving = KeyStage.arriving(after: log)
        let arrivingChanged = arriving.follow(to: back)
        #expect(!arrivingChanged)
        #expect(arriving == .arriving(after: log))
        // Below the edge, the next key is whatever face is live as it rises.
        #expect(arriving.face(for: back) == back)
    }

    @Test("Once gone, the next key is the live face below the edge; then it shows as the live one")
    func onceGone() {
        var stage = KeyStage.leaving(log)
        stage.advance(live: finish)
        #expect(stage == .arriving(after: log))
        #expect(stage.face(for: back) == back)
        stage.advance(live: back)
        #expect(stage == .showing(back))
        stage.advance(live: finish)
        #expect(stage == .showing(back))
    }

    @Test("Dropped out of sight, the key is in no swap and comes back as the live face")
    func dropped() {
        var stage = KeyStage.leaving(log)
        stage.drop(true, live: log)
        #expect(stage == .dropped)
        #expect(!stage.isOut)
        #expect(stage.face(for: finish) == finish)
        let changed = stage.follow(to: back)
        #expect(!changed)
        #expect(stage == .dropped)
        stage.drop(false, live: back)
        #expect(stage == .showing(back))
    }

    @Test("Dropped, a swap's beat that still runs changes nothing")
    func droppedIgnoresBeats() {
        var stage = KeyStage<Face>.dropped
        stage.advance(live: finish)
        #expect(stage == .dropped)
    }

    @Test("Back up from no drop, a showing key stays as it was")
    func undroppedShowing() {
        var stage = KeyStage.showing(log)
        stage.drop(false, live: finish)
        #expect(stage == .showing(log))
    }

    /// At the largest text sizes the way back's key wraps to two lines, taller than Log set's;
    /// the floating button above it moved to the next key's height before the key going had
    /// left, 108 pt in one frame.
    /// A button that dips is as far down over either key once both are out of sight, and takes
    /// the next one there; taken with the rise, at the largest text sizes it stepped by the keys'
    /// difference in height at the bottom (2026-11-25).
    @Test(
        "The floating button sits over the key drawn, or staying put, the one gone till a rise",
        arguments: [true, false],
    )
    func floatingFace(dips: Bool) {
        var stage = KeyStage.showing(log)
        #expect(stage.floatingFace(for: logRight, dips: dips) == logRight)
        #expect(stage.floatingFace(for: back, dips: dips) == log)
        _ = stage.follow(to: back)
        #expect(stage.floatingFace(for: back, dips: dips) == log)
        stage.advance(live: back)
        #expect(stage.floatingFace(for: back, dips: dips) == (dips ? back : log))
        stage.advance(live: back)
        #expect(stage.floatingFace(for: back, dips: dips) == back)
        stage.drop(true, live: finish)
        #expect(stage.floatingFace(for: finish, dips: dips) == finish)
    }

    @Test("A leaving or arriving key is out, and takes no tap; a showing one is in")
    func out() {
        #expect(!KeyStage.showing(log).isOut)
        #expect(KeyStage.leaving(log).isOut)
        #expect(KeyStage.arriving(after: log).isOut)
    }
}
