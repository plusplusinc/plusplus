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
        var arriving = KeyStage<Face>.arriving
        let arrivingChanged = arriving.follow(to: back)
        #expect(!arrivingChanged)
        #expect(arriving == .arriving)
        // Below the edge, the next key is whatever face is live as it rises.
        #expect(arriving.face(for: back) == back)
    }

    @Test("Once gone, the next key is the live face below the edge; then it shows as the live one")
    func onceGone() {
        var stage = KeyStage.leaving(log)
        stage.advance(live: finish)
        #expect(stage == .arriving)
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

    @Test("Back up from no drop, a showing key stays as it was")
    func undroppedShowing() {
        var stage = KeyStage.showing(log)
        stage.drop(false, live: finish)
        #expect(stage == .showing(log))
    }

    @Test("A leaving or arriving key is out, and takes no tap; a showing one is in")
    func out() {
        #expect(!KeyStage.showing(log).isOut)
        #expect(KeyStage.leaving(log).isOut)
        #expect(KeyStage<Face>.arriving.isOut)
    }
}
