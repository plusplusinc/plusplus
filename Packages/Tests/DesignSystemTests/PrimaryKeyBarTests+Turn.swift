// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// Something else landing at each frame of a swap: its key changed again, as Pause does; the
/// screen redrawn with no animation, as a sheet opening does; and the key taken away and brought
/// back. Each lands in the reaction to that frame's drawing, in the update that drew it, so the
/// frame it lands on is exact. Pause landing in the frame Log set's drop ended stood the rest's
/// keys at rest at once, then swapped them for Continue, and once left them down below the
/// screen's edge (2026-11-25).
///
/// Every case is its own window and hosting controller, so its updates are its own, and all of
/// them swap at once, a frame of the clock the test steps at a time (`KeyClock`): one swap's
/// frames for the lot, where one after another took 25 s.
extension PrimaryKeyBarTests {
    fileprivate struct Face: Equatable, Identifiable {
        let id: Int
        let words: String
    }

    fileprivate enum Landing: CaseIterable {
        /// The key changed again, to another kind, with no animation, as Pause.
        case change
        /// The screen redrawn with no animation and the key's inputs as they were, as a sheet.
        case redraw
        /// The key taken away, then brought back once it is gone.
        case takeAway
    }

    @Observable
    fileprivate final class TurnInputs {
        var face = Face(id: 1, words: "Log set")
        var isPresented = true
        /// Something the screen draws, which the bar doesn't.
        var redraws = 0
        /// The stepped clock's time at the host's last frame (`FrameTick`).
        @ObservationIgnored var drawnAt: TimeInterval?
        @ObservationIgnored let landing: Landing
        /// Which frame of the swap the landing comes on, counted from the first change.
        @ObservationIgnored let landsOn: Int
        @ObservationIgnored var frames = 0
        /// The key's depth as drawn on each frame of the swap, its swap's and its going's parts.
        @ObservationIgnored var drawn: [KeyReach.Parts] = []

        init(landing: Landing, landsOn: Int) {
            self.landing = landing
            self.landsOn = landsOn
        }

        var landed: Bool {
            frames >= landsOn
        }

        /// The frame the key going was first drawn all the way down on.
        var bottom: Int? {
            drawn.firstIndex { $0.swap >= 1 }.map { $0 + 1 }
        }

        /// Notes a frame drawn, as nothing to see.
        func noteFrame() -> Color {
            drawnAt = KeyClock.stepped?.now
            return .clear
        }

        func land() {
            switch landing {
            case .change: face = Face(id: 3, words: "Continue")
            case .redraw: redraws += 1
            case .takeAway: isPresented = false
            }
        }
    }

    /// A view beside the bar that notes the stepped clock's time each time the host draws a
    /// frame, so the test steps the clock only once every case has drawn the step before. A
    /// hosted view draws an animation's frames only on the display's, never on a layout pass.
    /// It redraws alone, not the screen around the bar, as a ticking timer does.
    fileprivate struct FrameTick: View {
        let inputs: TurnInputs

        var body: some View {
            TimelineView(.animation) { _ in
                inputs.noteFrame()
            }
        }
    }

    fileprivate struct TurnHost: View {
        let inputs: TurnInputs

        var body: some View {
            // Read, so a change redraws the screen around the bar.
            Color.clear.tag(inputs.redraws)
                .background { FrameTick(inputs: inputs) }
                .primaryKeyBar(
                    isPresented: inputs.isPresented,
                    face: inputs.face,
                    keepsRoom: true,
                ) { face, isOut in
                    Button(face.words) { }
                        .accessibilityValue(isOut ? "out" : "")
                }
                // Once per frame the key moves, in the update that drew it.
                .onPreferenceChange(KeyTrayDrawn.self) { drawn in
                    guard inputs.face.id != 1 || inputs.frames > 0 else { return }
                    inputs.frames += 1
                    inputs.drawn.append(drawn.parts)
                    if inputs.frames == inputs.landsOn {
                        inputs.land()
                    }
                }
        }
    }

    private struct Seen {
        let words: String
        let isOut: Bool
        let top: CGFloat
    }

    /// One case, hosted.
    @MainActor
    private struct Case {
        let inputs: TurnInputs
        let host: UIHostingController<TurnHost>
        let window: UIWindow
        let live: String
        var rest: CGFloat = 0

        init(_ landing: Landing, onFrame frame: Int) {
            inputs = TurnInputs(landing: landing, landsOn: frame)
            host = UIHostingController(rootView: TurnHost(inputs: inputs))
            window = UIWindow.sceneless(hosting: host, at: .large)
            live = landing == .change ? "Continue" : "Skip rest"
        }

        /// The key as automation reads it.
        func seen() -> Seen? {
            AccessibilityTree.leaves(under: host.view).first { $0.accessibilityLabel != nil }
                .map {
                    Seen(
                        words: $0.accessibilityLabel ?? "",
                        isOut: $0.accessibilityValue == "out",
                        top: $0.accessibilityFrame.minY,
                    )
                }
        }

        /// Whether the key going and coming is drawn at rest, at the end of the swap.
        var isStill: Bool {
            guard landed, let last = inputs.drawn.last else { return false }
            return last == KeyReach.Parts(swap: 0, away: 0, drop: 0) && inputs.isPresented
        }

        var landed: Bool {
            inputs.landed
        }
    }

    /// Through the drop, its turn, and the rise's first frames, at the default text size: the
    /// drop is 12 frames at 60 Hz, and each case checks the turn came within them.
    private nonisolated static let swapFrames = Array(1 ... 16)
    /// One frame at 60 Hz.
    private nonisolated static let frame = 1.0 / 60

    /// On a clock stepped a frame at a time (`KeyClock`), so a frame is a frame however busy
    /// the host: sampled in real time, a slow host drew the swap in fewer frames than the last
    /// cases land on, and nothing landed.
    @Test("Something landing on any frame of a swap leaves the live key risen to rest")
    func landingOnAnyFrame() throws {
        let clock = SteppedClock()
        KeyClock.stepped = clock
        defer { KeyClock.stepped = nil }
        try AccessibilityTree.whileOn {
            var cases = Landing.allCases.flatMap { landing in
                Self.swapFrames.map { Case(landing, onFrame: $0) }
            }
            defer { cases.forEach { $0.window.isHidden = true } }
            for index in cases.indices {
                cases[index].window.settle()
                cases[index].rest = try #require(cases[index].seen()).top
            }
            for item in cases {
                item.inputs.face = Face(id: 2, words: "Skip rest")
            }
            // Twice the swap and a key's going and coming back is far past the last landing.
            for _ in 0 ..< Int(8 * PrimaryKeyButtonStyle.swapHalf / Self.frame) {
                for item in cases {
                    item.window.layoutIfNeeded()
                    if item.landed, !item.inputs.isPresented, item.inputs.drawn.last?.away == 1 {
                        withAnimation(KeyClock.pace(.easeInOut(duration: 0.2))) {
                            item.inputs.isPresented = true
                        }
                    }
                }
                if cases.allSatisfy(\.isStill) {
                    break
                }
                clock.advance(by: Self.frame)
                try drawAll(cases, at: clock.now)
            }
            for item in cases {
                check(item)
            }
        }
    }

    /// Turns the run loop until every case's host has drawn a frame at `time`, as the display
    /// asks for one; a second for them all is far past a frame on any host.
    private func drawAll(_ cases: [Case], at time: TimeInterval) throws {
        let limit = ContinuousClock.now + .seconds(1)
        while cases.contains(where: { $0.inputs.drawnAt != time }), ContinuousClock.now < limit {
            RunLoop.main.run(mode: .default, before: .now.addingTimeInterval(Self.frame / 4))
        }
        let undrawn = cases.filter { $0.inputs.drawnAt != time }.count
        try #require(undrawn == 0, "\(undrawn) hosts drew no frame in a second")
    }

    /// The case's key ends live and at rest, its frames reached past the turn, and it never
    /// stood at rest at once from all the way down.
    private func check(_ item: Case) {
        let name = "\(item.inputs.landing) on frame \(item.inputs.landsOn)"
        let inputs = item.inputs
        #expect(inputs.landed, "\(name): nothing landed, the swap had \(inputs.frames)")
        if inputs.landsOn == Self.swapFrames.last {
            #expect((inputs.bottom ?? .max) < inputs.landsOn, "\(name): the frames miss the turn")
        }
        let seen = item.seen()
        #expect(
            seen?.words == item.live && seen?.isOut == false
                && abs((seen?.top ?? 0) - item.rest) < 0.5,
            "\(name): the key ended as \(String(describing: seen))",
        )
        // Down by the key's going and its swap together: a rise moves through its frames, and
        // a key standing at rest at once comes up from all the way down in one.
        let depths = inputs.drawn.map { $0.swap + $0.away }
        let steps = zip(depths, depths.dropFirst()).map { $0 - $1 }
        let jump = steps.max() ?? 0
        let at = (steps.firstIndex(of: jump) ?? 0) + 2
        #expect(jump < 0.99, "\(name): the key came up \(jump) on its frame \(at): \(depths)")
    }
}

#endif
