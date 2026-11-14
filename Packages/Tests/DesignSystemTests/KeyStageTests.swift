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

    @Test("Within a kind, the key stays showing and draws the live words")
    func withinAKind() {
        var stage = KeyStage.showing(log)
        stage.follow(logRight, isPresented: true)
        #expect(stage == .showing(logRight))
        #expect(stage.face(for: logRight) == logRight)
    }

    @Test("A change of kind starts the key leaving, drawing the old words whatever is live")
    func changeOfKind() {
        var stage = KeyStage.showing(log)
        stage.follow(finish, isPresented: true)
        #expect(stage == .leaving(log, next: finish))
        #expect(stage.face(for: finish) == log)
        #expect(stage.face(for: back) == log)
    }

    @Test("Before the reaction has run, a showing key given another kind draws the face it had")
    func beforeTheReaction() {
        #expect(KeyStage.showing(log).face(for: finish) == log)
    }

    @Test("While leaving, further changes move only what comes next")
    func whileLeaving() {
        var stage = KeyStage.leaving(log, next: finish)
        stage.follow(back, isPresented: true)
        #expect(stage == .leaving(log, next: back))
        #expect(stage.face(for: back) == log)
    }

    @Test("Once gone, the next key is the face live then, below the edge; then it shows")
    func onceGone() {
        var stage = KeyStage.leaving(log, next: finish)
        stage.follow(back, isPresented: true)
        stage.advance()
        #expect(stage == .arriving(back))
        stage.advance()
        #expect(stage == .showing(back))
        stage.advance()
        #expect(stage == .showing(back))
    }

    @Test("A change of kind while the next key is below the edge makes it that key")
    func whileArriving() {
        var stage = KeyStage.arriving(finish)
        stage.follow(back, isPresented: true)
        #expect(stage == .arriving(back))
        #expect(stage.face(for: back) == back)
    }

    @Test("A change of kind once showing again starts another leave")
    func anotherLeave() {
        var stage = KeyStage.arriving(finish)
        stage.advance()
        stage.follow(log, isPresented: true)
        #expect(stage == .leaving(finish, next: log))
    }

    @Test("Not presented, any change from any stage becomes showing the live face")
    func notPresented() {
        for start in [KeyStage.showing(log), .leaving(log, next: finish), .arriving(finish)] {
            var stage = start
            stage.follow(back, isPresented: false)
            #expect(stage == .showing(back))
        }
    }

    @Test("Only a showing key takes taps; a leaving or arriving one is out")
    func taps() {
        #expect(KeyStage.showing(log).takesTaps)
        #expect(!KeyStage.showing(log).isOut)
        #expect(KeyStage.leaving(log, next: finish).isOut)
        #expect(!KeyStage.leaving(log, next: finish).takesTaps)
        #expect(KeyStage.arriving(finish).isOut)
        #expect(!KeyStage.arriving(finish).takesTaps)
    }
}
