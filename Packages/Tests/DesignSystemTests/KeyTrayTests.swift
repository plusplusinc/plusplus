import CoreGraphics
import Testing
@testable import DesignSystem

/// How a bar's key swaps for another, goes away, and comes back, and where the floating button
/// rides above it, from plain values.
@Suite("Key tray")
struct KeyTrayTests {
    private struct Face: Equatable, Identifiable {
        let id: Int
        let words: String
    }

    private typealias Tray = KeyTray<Face>
    private typealias Inputs = Tray.Inputs

    private let log = Face(id: 1, words: "Log set")
    private let logRight = Face(id: 1, words: "Log right")
    private let back = Face(id: 2, words: "Bench press")
    private let finish = Face(id: 3, words: "Finish workout")

    private func shown(_ face: Face) -> Inputs {
        Inputs(face: face, isPresented: true)
    }

    private func away(_ face: Face) -> Inputs {
        Inputs(face: face, isPresented: false)
    }

    @Test("Showing, the same key's new words draw at once and are followed in place")
    func withinAKind() {
        var tray = Tray(shown(log))
        tray.follow(shown(logRight))
        #expect(tray.face == logRight)
        #expect(!tray.needsSwap)
        #expect(tray.stage == .showing(logRight))
    }

    @Test("Another key's face, before the swap starts, draws the key as it was")
    func beforeFollowing() {
        var tray = Tray(shown(logRight))
        tray.follow(shown(finish))
        #expect(tray.needsSwap)
        #expect(tray.face == logRight)
    }

    @Test("A change of kind starts the key leaving, drawing its own words whatever is live")
    func changeOfKind() {
        var tray = Tray(shown(logRight))
        tray.follow(shown(finish))
        tray.startLeaving()
        #expect(tray.stage == .leaving(logRight))
        #expect(tray.isOut)
        tray.follow(shown(back))
        #expect(tray.face == logRight)
    }

    @Test("While leaving or arriving, further changes change nothing; the next key is the live one")
    func whileOut() {
        var tray = Tray(shown(log))
        tray.follow(shown(back))
        tray.startLeaving()
        tray.follow(shown(finish))
        #expect(tray.stage == .leaving(log))
        tray.advance()
        tray.follow(shown(back))
        #expect(tray.stage == .arriving)
        // Below the edge, the next key is whatever face is live as it rises.
        #expect(tray.face == back)
    }

    @Test("Once gone, the next key is the live face below the edge; then it shows as the live one")
    func onceGone() {
        var tray = Tray(shown(log))
        tray.follow(shown(finish))
        tray.startLeaving()
        tray.advance()
        #expect(tray.stage == .arriving)
        tray.follow(shown(back))
        tray.advance()
        #expect(tray.stage == .showing(back))
        tray.advance()
        #expect(tray.stage == .showing(back))
    }

    @Test("Away, the key is in no swap, keeps the face it left with, and ignores the swap's beats")
    func awayIgnoresBeats() {
        var tray = Tray(shown(log))
        tray.follow(shown(back))
        tray.startLeaving()
        tray.follow(Inputs(face: back, isPresented: true, isDropped: true))
        #expect(tray.stage == .away(log))
        #expect(!tray.isOut)
        tray.advance()
        #expect(tray.stage == .away(log))
        tray.follow(away(finish))
        #expect(tray.face == log)
    }

    /// Skip rest between two sets: its keys go at the tap as the next key comes due, and Log set
    /// is presented while they are still on their way down. Put back as the key going, Log set
    /// came back up as Skip rest and swapped (2026-11-25).
    @Test(
        "Taken away as it changes kind, the key goes with its words; back, it is the live key",
    )
    func awayAsItChangesKind() {
        var tray = Tray(shown(back))
        tray.follow(away(log))
        #expect(tray.face == back)
        #expect(tray.drawn(for: away(log)).targets.away == 1)
        tray.follow(shown(log))
        #expect(tray.stage == .showing(log))
        #expect(!tray.needsSwap)
        #expect(!tray.drawn(for: shown(log)).isOut)
    }

    @Test("Following the same inputs twice changes nothing")
    func followIsIdempotent() {
        for inputs in [shown(log), shown(back), away(finish), shown(finish)] {
            var tray = Tray(shown(log))
            tray.follow(inputs)
            let once = tray
            tray.follow(inputs)
            #expect(tray == once, "\(inputs)")
        }
    }

    @Test("Taken away mid-swap, the key leaves the swap and its depth only grows")
    func awayMidSwap() {
        let reach = KeyReach(swapBelow: 12, bottomInset: 34, drop: 0, gap: 16)
        var tray = Tray(shown(log))
        tray.follow(shown(back))
        tray.startLeaving()
        let swapping = tray.drawn(for: shown(back)).targets
        tray.follow(away(back))
        let gone = tray.drawn(for: away(back)).targets
        #expect(gone.swap == 0 && gone.away == 1)
        #expect(reach.depth(gone, height: 56) > reach.depth(swapping, height: 56))
    }

    @Test("A leaving or arriving key is out, and takes no tap; a showing or away one is not")
    func out() {
        var tray = Tray(shown(log))
        #expect(!tray.isOut)
        tray.follow(shown(back))
        tray.startLeaving()
        #expect(tray.isOut)
        tray.advance()
        #expect(tray.isOut)
        tray.follow(away(back))
        #expect(!tray.isOut)
    }

    @Test("Ridden out of sight, the key comes back as the live face, in no swap")
    func droppedComesBackLive() {
        var tray = Tray(Inputs(face: Face(id: 0, words: "Start"), isPresented: true))
        tray.follow(Inputs(face: Face(id: 0, words: "Start"), isPresented: true, isDropped: true))
        tray.follow(away(log))
        tray.follow(shown(log))
        #expect(tray.stage == .showing(log))
    }

    // MARK: The floating button

    private nonisolated static let reaches = [
        KeyReach(swapBelow: 12, bottomInset: 34, drop: 0, gap: 16),
        KeyReach(swapBelow: 21, bottomInset: 0, drop: 800, gap: 16),
    ]

    @Test(
        "The floating button keeps its gap above the key down to its low place, and stays",
        arguments: reaches,
    )
    func floatingRidesTheKey(reach: KeyReach) {
        for height in [56, 108, 160] as [CGFloat] {
            var lastLift = CGFloat.infinity
            for step in 0 ... 40 {
                let progress = CGFloat(step) / 40
                for parts in [
                    KeyReach.Parts(swap: progress, away: 0, drop: 0),
                    KeyReach.Parts(swap: 0, away: progress, drop: 0),
                    KeyReach.Parts(swap: 0, away: 0, drop: progress),
                ] {
                    let lift = reach.floatingLift(parts, height: height)
                    let keyTop = reach.depth(parts, height: height) - height
                    let floatingBottom = -lift
                    #expect(lift >= 0)
                    if lift > 0 {
                        #expect(abs(keyTop - floatingBottom - reach.gap) < 0.001)
                    }
                }
                // Going only down, the button never rises.
                let lift = reach.floatingLift(
                    KeyReach.Parts(swap: 0, away: progress, drop: 0),
                    height: height,
                )
                #expect(lift <= lastLift)
                lastLift = lift
            }
            #expect(reach
                .floatingLift(KeyReach.Parts(swap: 0, away: 1, drop: 0), height: height) == 0)
        }
    }

    /// At the largest text sizes the keys either side of a swap differ in height; where they
    /// meet at the screen's edge, the button stepped by the difference (2026-11-25).
    @Test("At a swap's bottom the floating button is in the same place for a key of any height")
    func swapBottomIgnoresHeight() {
        let reach = Self.reaches[0]
        let bottom = KeyReach.Parts(swap: 1, away: 0, drop: 0)
        let lifts = [56, 108, 160].map { reach.floatingLift(bottom, height: $0) }
        #expect(Set(lifts).count == 1, "\(lifts)")
    }

    @Test(
        "With Reduce Motion, nothing travels: the key stays put, the button at one of two places",
    )
    func reduceMotion() {
        let reach = Self.reaches[0]
        for progress in [0, 0.3, 1] as [CGFloat] {
            let swap = KeyReach.Parts(swap: progress, away: 0, drop: 0)
            let gone = KeyReach.Parts(swap: 0, away: progress, drop: 0)
            #expect(reach.depth(swap, height: 56, reduceMotion: true) == 0)
            #expect(reach.depth(gone, height: 56, reduceMotion: true) == 0)
            #expect(reach.floatingLift(swap, height: 56, reduceMotion: true) == 56 + reach.gap)
            #expect(
                reach.floatingLift(gone, height: 56, reduceMotion: true, inSight: false) == 0,
            )
        }
    }
}
