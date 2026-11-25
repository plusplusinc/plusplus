// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// The floating button through a swap of the bar's key, read frame by frame as automation reads
/// both, over the swap's real time: the swap's motion is what's tested.
extension PrimaryKeyBarTests {
    fileprivate struct Face: Equatable, Identifiable {
        let id: Int
        let words: String
    }

    @Observable
    fileprivate final class DipInputs {
        var face = Face(id: 1, words: "Log set")
        var floatsLow = false
    }

    fileprivate struct DipHost: View {
        let inputs: DipInputs

        var body: some View {
            Color.clear
                .primaryKeyBar(
                    isPresented: true,
                    face: inputs.face,
                    floatsLow: inputs.floatsLow,
                ) { face, isOut in
                    // A face's words on lines of their own make a taller key, as a rest's keys
                    // are at the largest text sizes.
                    Button(face.words) { }
                        .accessibilityValue(isOut ? "out" : "")
                } floating: {
                    Button("Add exercise", systemImage: "plus") { }
                }
        }
    }

    /// The key and the floating button as automation reads them at one moment; the key is nil
    /// while none is drawn.
    fileprivate struct Sample {
        let key: CGRect?
        let isOut: Bool
        let floating: CGRect

        /// How far the floating button's bottom is above the key's top.
        var gap: CGFloat? {
            key.map { $0.minY - floating.maxY }
        }
    }

    /// How a swap went: the bar at rest before it, and every sample after the change.
    fileprivate struct Run {
        let rest: Sample
        let samples: [Sample]

        /// How far the floating button is drawn below where it rested, sample by sample.
        var floatingDrop: [CGFloat] {
            samples.map { $0.floating.minY - rest.floating.minY }
        }
    }

    /// Hosts the bar on Log set, changes it by `change`, and samples it until `isDone` says
    /// it has settled, failing if it hasn't within a few swaps' length.
    private func run(
        _ change: (DipInputs) -> Void,
        until isDone: (_ now: Sample, _ rest: Sample) -> Bool,
    ) async throws -> Run {
        try await AccessibilityTree.whileOn {
            let inputs = DipInputs()
            let host = UIHostingController(rootView: DipHost(inputs: inputs))
            let window = UIWindow.sceneless(hosting: host, at: .large)
            defer { window.isHidden = true }
            window.settle()
            @MainActor func sample() throws -> Sample {
                let leaves = AccessibilityTree.leaves(under: host.view)
                let floating = leaves.first { $0.accessibilityLabel == "Add exercise" }
                let key = leaves.first {
                    $0.accessibilityLabel != "Add exercise" && $0.accessibilityLabel != nil
                }
                return try Sample(
                    key: key?.accessibilityFrame,
                    isOut: key?.accessibilityValue == "out",
                    floating: #require(floating, "the floating button went from the tree")
                        .accessibilityFrame,
                )
            }
            let rest = try sample()
            change(inputs)
            var samples: [Sample] = []
            let limit = ContinuousClock.now + .seconds(10 * PrimaryKeyButtonStyle.swapHalf)
            while ContinuousClock.now < limit {
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(4))
                let now = try sample()
                samples.append(now)
                if isDone(now, rest) {
                    return Run(rest: rest, samples: samples)
                }
            }
            Issue.record("the bar never came to rest: \(samples.suffix(3))")
            return Run(rest: rest, samples: samples)
        }
    }

    /// Settled: a key in, risen to the bottom it rested on, and the floating button `gap` above it.
    private static func risen(_ now: Sample, _ rest: Sample) -> Bool {
        guard let key = now.key, let restKey = rest.key, let gap = now.gap, let restGap = rest.gap
        else { return false }
        return !now.isOut && abs(key.maxY - restKey.maxY) < 0.5 && abs(gap - restGap) < 0.5
    }

    /// Through a swap, the button stays as far above the key as it rests, on every sample the
    /// key is drawn, so the two move as one piece.
    private func expectOnePiece(_ run: Run) throws {
        let restGap = try #require(run.rest.gap)
        for sample in run.samples {
            guard let gap = sample.gap else { continue }
            #expect(abs(gap - restGap) < 1, "the button and the key parted: \(sample)")
        }
    }

    @Test("Through a swap, the floating button goes down and back up with the keys, as one piece")
    func floatingDipsWithSwap() async throws {
        let run = try await run({ $0.face = Face(id: 2, words: "Skip rest") }, until: Self.risen)
        let deepest = try #require(run.floatingDrop.max())
        #expect(deepest > 40, "the floating button never went down: \(deepest)")
        try expectOnePiece(run)
        let end = try #require(run.floatingDrop.last)
        #expect(abs(end) < 0.5, "it didn't come back where it began: \(end)")
    }

    /// At the largest text sizes a rest's keys are taller than Log set. The button took the
    /// difference in one frame where the keys met at the screen's edge, then closed it against
    /// the key coming up (2026-11-25).
    @Test("Through a swap for a taller key, the floating button keeps its gap above both keys")
    func floatingDipsWithTallerKey() async throws {
        let taller = Face(id: 2, words: "Skip\nrest\nnow")
        let run = try await run({ $0.face = taller }, until: Self.risen)
        try expectOnePiece(run)
        let end = try #require(run.samples.last?.key)
        let start = try #require(run.rest.key)
        #expect(end.height > start.height + 20, "the second key wasn't taller: \(end)")
    }

    /// As a key leaves with none to follow, the screen sets the button low on the same update:
    /// it goes down once and stays, rather than dipping with the swap and coming back up first.
    @Test("Going low as the key swaps, the floating button only goes down")
    func floatingGoesLowOnce() async throws {
        let run = try await run { inputs in
            withAnimation(.easeInOut(duration: 0.3)) {
                inputs.face = Face(id: 2, words: "Skip rest")
                inputs.floatsLow = true
            }
        } until: { now, rest in
            // The next key risen, by when the button's own move has long ended.
            guard let key = now.key, let restKey = rest.key else { return false }
            return !now.isOut && abs(key.maxY - restKey.maxY) < 0.5
        }
        let path = run.floatingDrop
        #expect(zip(path, path.dropFirst()).allSatisfy { $1 >= $0 }, "it went back up: \(path)")
        #expect((path.last ?? 0) > 40, "it never went low: \(path)")
    }

    /// No swap, so nothing to wait on: sampled for as long as a swap would take.
    @Test("Within a kind, the floating button stays put as the words change")
    func floatingStillWithinKind() async throws {
        let end = ContinuousClock.now + .seconds(2 * PrimaryKeyButtonStyle.swapHalf)
        let run = try await run {
            $0.face = Face(id: 1, words: "Log right")
        } until: { _, _ in
            ContinuousClock.now > end
        }
        #expect(run.floatingDrop.allSatisfy { $0 == 0 }, "the button moved")
    }
}

#endif
