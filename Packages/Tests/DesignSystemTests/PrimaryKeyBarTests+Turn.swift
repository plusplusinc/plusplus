// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// Something else landing at each frame of a swap: its key changed again, as Pause does; the
/// screen redrawn with no animation, as a sheet opening does; and the key taken away and brought
/// back. Each lands in the reaction to that frame's drawing, in the update that drew it, so the
/// frame it lands on is exact; read as automation reads the key, over the swap's real time. Pause
/// landing in the frame Log set's drop ended stood the rest's keys at rest at once, then swapped
/// them for Continue, and once left them down below the screen's edge (2026-11-25).
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
        /// The key taken away, then brought back as the bar comes to rest.
        case takeAway
    }

    @Observable
    fileprivate final class TurnInputs {
        var face = Face(id: 1, words: "Log set")
        var isPresented = true
        /// Something the screen draws, which the bar doesn't.
        var redraws = 0
        /// Which frame of the swap `land` runs on, counted from the first change.
        @ObservationIgnored var landsOn = 0
        @ObservationIgnored var frames = 0
        @ObservationIgnored var landed = false
        @ObservationIgnored var land: (TurnInputs) -> Void = { _ in }
    }

    fileprivate struct TurnHost: View {
        let inputs: TurnInputs

        var body: some View {
            // Read, so a change redraws the screen around the bar.
            Color.clear.tag(inputs.redraws)
                .primaryKeyBar(
                    isPresented: inputs.isPresented,
                    face: inputs.face,
                    keepsRoom: true,
                ) { face, isOut in
                    Button(face.words) { }
                        .accessibilityValue(isOut ? "out" : "")
                }
                // Once per frame the key moves, in the update that drew it.
                .onPreferenceChange(KeyTrayDrawn.self) { _ in
                    inputs.frames += 1
                    if !inputs.landed, inputs.frames == inputs.landsOn {
                        inputs.landed = true
                        inputs.land(inputs)
                    }
                }
        }
    }

    /// The key as automation reads it.
    private struct Seen: Equatable {
        let words: String
        let isOut: Bool
        let top: CGFloat
    }

    /// Swaps Log set for Skip rest with `landing` on frame `frame` of it, then samples the key
    /// until it is at rest as the key that is live, failing if it never is or if it jumps up.
    private func swap(landing: Landing, onFrame frame: Int) async throws {
        try await AccessibilityTree.whileOn {
            let inputs = TurnInputs()
            let host = UIHostingController(rootView: TurnHost(inputs: inputs))
            let window = UIWindow.sceneless(hosting: host, at: .large)
            defer { window.isHidden = true }
            window.settle()
            @MainActor func seen() -> Seen? {
                AccessibilityTree.leaves(under: host.view).first { $0.accessibilityLabel != nil }
                    .map {
                        Seen(
                            words: $0.accessibilityLabel ?? "",
                            isOut: $0.accessibilityValue == "out",
                            top: $0.accessibilityFrame.minY,
                        )
                    }
            }
            let rest = try #require(seen()).top
            let live = landing == .change ? "Continue" : "Skip rest"
            inputs.landsOn = frame
            inputs.frames = 0
            inputs.land = { inputs in
                switch landing {
                case .change: inputs.face = Face(id: 3, words: "Continue")
                case .redraw: inputs.redraws += 1
                case .takeAway: inputs.isPresented = false
                }
            }
            inputs.face = Face(id: 2, words: "Skip rest")
            var samples: [Seen?] = []
            var broughtBack = false
            let limit = ContinuousClock.now + .seconds(15 * PrimaryKeyButtonStyle.swapHalf)
            while ContinuousClock.now < limit {
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(4))
                let now = seen()
                samples.append(now)
                if landing == .takeAway, inputs.landed, !broughtBack, now == nil {
                    broughtBack = true
                    withAnimation(.easeInOut(duration: 0.3)) { inputs.isPresented = true }
                }
                if inputs.landed, let now, now.words == live, !now.isOut,
                   abs(now.top - rest) < 0.5
                {
                    break
                }
            }
            let trail = "frame \(frame): \(samples.suffix(4))"
            #expect(
                inputs.landed,
                "nothing landed on frame \(frame): the swap had \(inputs.frames)",
            )
            let ending: Seen? = samples.last.flatMap { $0 }
            let last = try #require(ending, "no key at the end, \(trail)")
            #expect(last.words == live && !last.isOut, "the key ended wrong, \(trail)")
            #expect(abs(last.top - rest) < 0.5, "the key never came to rest, \(trail)")
            // Up only by a rise's step: a key standing at rest at once moved its whole drop.
            let tops = samples.compactMap { $0?.top }
            let jump = zip(tops, tops.dropFirst()).map { $0 - $1 }.max() ?? 0
            #expect(jump < 40, "the key jumped up \(jump) pt, frame \(frame): \(tops)")
        }
    }

    /// Through the drop, its turn, and the rise's first frames, at the default text size.
    private nonisolated static let swapFrames = Array(1 ... 20)

    @Test(
        "A key changed again on any frame of a swap rises as the new key and comes to rest",
        arguments: swapFrames,
    )
    func changeOnAnyFrame(frame: Int) async throws {
        try await swap(landing: .change, onFrame: frame)
    }

    @Test(
        "A screen redrawn with no animation on any frame of a swap leaves it rising to rest",
        arguments: swapFrames,
    )
    func redrawOnAnyFrame(frame: Int) async throws {
        try await swap(landing: .redraw, onFrame: frame)
    }

    @Test(
        "A key taken away on any frame of a swap comes back as the live key, at rest",
        arguments: swapFrames,
    )
    func takeAwayOnAnyFrame(frame: Int) async throws {
        try await swap(landing: .takeAway, onFrame: frame)
    }
}

#endif
