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
        #expect(tray.stage == .showing(logRight))
        #expect(tray.swaps == 0)
    }

    @Test("A change of kind starts the key leaving, drawing its own words whatever is live")
    func changeOfKind() {
        var tray = Tray(shown(logRight))
        tray.follow(shown(finish))
        #expect(tray.stage == .leaving(logRight))
        #expect(tray.isOut)
        tray.follow(shown(back))
        #expect(tray.face == logRight)
    }

    @Test("While leaving, further changes change nothing; the key that turns is the live one")
    func whileOut() {
        var tray = Tray(shown(log))
        tray.follow(shown(back))
        tray.follow(shown(finish))
        #expect(tray.stage == .leaving(log))
        tray.follow(shown(finish), down: tray.swaps)
        #expect(tray.stage == .showing(finish))
    }

    @Test("A swap turns once its own drop is drawn down, and only then")
    func turnIsItsSwaps() {
        var tray = Tray(shown(log))
        tray.follow(shown(finish))
        let first = tray.swaps
        tray.follow(away(finish))
        tray.follow(shown(log))
        tray.follow(shown(back))
        // The first swap's drop drawn down, come after it was taken away and another started.
        tray.follow(shown(back), down: first)
        #expect(tray.stage == .leaving(log))
        tray.follow(shown(back), down: tray.swaps)
        #expect(tray.stage == .showing(back))
        tray.follow(shown(back), down: tray.swaps)
        #expect(tray.stage == .showing(back))
    }

    /// Pause landing in the frame Log set's drop ended: the turn and the next swap's start came
    /// in one update, with the key already drawn down, and nothing changed for the turn to wait
    /// on (2026-11-25). The next swap turns on its own drop drawn down, which is news as its
    /// number, never on the last one's still standing.
    @Test("A swap started as the last one turns waits for its own drop, not the last one's")
    func swapAtTheTurn() {
        var tray = Tray(shown(log))
        tray.follow(shown(back))
        let first = tray.swaps
        tray.follow(shown(back), down: first)
        tray.follow(shown(finish), down: first)
        #expect(tray.stage == .leaving(back))
        let drawn = tray.drawn(for: shown(finish)).swap
        #expect(drawn.number != first && drawn.depth == 1)
        tray.follow(shown(finish), down: drawn.number)
        #expect(tray.stage == .showing(finish))
    }

    @Test("A swap goes down at the drop's pace and up at the rise's; away, at the screen's")
    func swapPace() {
        var tray = Tray(shown(log))
        #expect(tray.drawn(for: shown(log)).swap.pace == .rise)
        tray.follow(shown(back))
        #expect(tray.drawn(for: shown(back)).swap.pace == .drop)
        tray.follow(shown(back), down: tray.swaps)
        #expect(tray.drawn(for: shown(back)).swap.pace == .rise)
        tray.follow(shown(finish))
        tray.follow(away(finish))
        #expect(tray.drawn(for: away(finish)).swap == SwapDrawn(
            number: tray.swaps,
            depth: 0,
            pace: .update,
        ))
    }

    @Test("Away, the key is in no swap, keeps the face it left with, and ignores the swap's turn")
    func awayIgnoresTurn() {
        var tray = Tray(shown(log))
        tray.follow(shown(back))
        let dropped = Inputs(face: back, isPresented: true, isDropped: true)
        tray.follow(dropped)
        #expect(tray.stage == .away(log))
        #expect(!tray.isOut)
        tray.follow(dropped, down: tray.swaps)
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
        #expect(tray.drawn(for: away(log)).away == 1)
        tray.follow(shown(log))
        #expect(tray.stage == .showing(log))
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
        let reach = KeyReach(swapBelow: 12, bottomInset: 34, gap: 16)
        var tray = Tray(shown(log))
        tray.follow(shown(back))
        let parts = { (drawn: Tray.Drawn) in
            KeyReach.Parts(swap: drawn.swap.depth, away: drawn.away, drop: 0)
        }
        let swapping = parts(tray.drawn(for: shown(back)))
        tray.follow(away(back))
        let gone = parts(tray.drawn(for: away(back)))
        #expect(gone.swap == 0 && gone.away == 1)
        #expect(reach.depth(gone, height: 56) > reach.depth(swapping, height: 56))
    }

    @Test("A leaving key is out, and takes no tap; a showing, rising, or away one is not")
    func out() {
        var tray = Tray(shown(log))
        #expect(!tray.isOut)
        tray.follow(shown(back))
        #expect(tray.isOut)
        tray.follow(shown(back), down: tray.swaps)
        #expect(!tray.isOut)
        tray.follow(shown(log))
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
        KeyReach(swapBelow: 12, bottomInset: 34, gap: 16),
        KeyReach(swapBelow: 21, bottomInset: 0, gap: 16),
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
