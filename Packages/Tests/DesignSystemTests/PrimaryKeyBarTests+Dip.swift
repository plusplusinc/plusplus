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
        var isPresented = true
    }

    fileprivate struct DipHost: View {
        let inputs: DipInputs

        var body: some View {
            Color.clear
                .primaryKeyBar(
                    isPresented: inputs.isPresented,
                    face: inputs.face,
                    keepsRoom: true,
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

    /// Hosts the bar on Log set, or as `setup` leaves it, changes it by `change`, and samples it
    /// until `isDone` says it has settled, failing if it hasn't within a few swaps' length.
    private func run(
        from setup: (DipInputs) -> Void = { _ in },
        _ change: (DipInputs) -> Void,
        until isDone: (_ now: Sample, _ rest: Sample) -> Bool,
    ) async throws -> Run {
        try await AccessibilityTree.whileOn {
            let inputs = DipInputs()
            setup(inputs)
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

    /// A key in, risen to the bottom the key before it rested on.
    private static func keyIn(_ now: Sample, _ rest: Sample) -> Bool {
        guard let key = now.key, let restKey = rest.key else { return false }
        return !now.isOut && abs(key.maxY - restKey.maxY) < 0.5
    }

    /// Settled: a key in, and the floating button as far above it as it rested.
    private static func risen(_ now: Sample, _ rest: Sample) -> Bool {
        guard keyIn(now, rest), let gap = now.gap, let restGap = rest.gap else { return false }
        return abs(gap - restGap) < 0.5
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

    /// As a key leaves with none to follow, changing kind as it goes, as Skip rest into "Start
    /// in": the button rides down once and stays low, rather than dipping with a swap and
    /// coming back up first.
    @Test("As the key is taken away, the floating button only goes down, and stays low")
    func floatingGoesLowOnce() async throws {
        // For as long as a swap would take, by when the key's move has long ended.
        let end = ContinuousClock.now + .seconds(3 * PrimaryKeyButtonStyle.swapHalf)
        let run = try await run { inputs in
            withAnimation(.easeInOut(duration: 0.3)) {
                inputs.face = Face(id: 2, words: "Skip rest")
                inputs.isPresented = false
            }
        } until: { _, _ in
            ContinuousClock.now > end
        }
        let path = run.floatingDrop
        #expect(zip(path, path.dropFirst()).allSatisfy { $1 >= $0 }, "it went back up: \(path)")
        #expect((path.last ?? 0) > 40, "it never went low: \(path)")
    }

    /// A key coming in, as "Start in" ends, Continue comes up, or Log set after Skip rest: the
    /// button rose on its own layout change, 78 pt, while the key came 96 pt by its transition,
    /// and the two parted on the way (2026-11-25).
    @Test(
        "An arriving key and the floating button come up as one piece",
        arguments: ["Log set", "Log\nset\nnow"],
    )
    func arrivalIsOnePiece(words: String) async throws {
        // For as long as the rise and a frame or two after it.
        let end = ContinuousClock.now + .seconds(0.3 + 2 * PrimaryKeyButtonStyle.swapHalf)
        let away: (DipInputs) -> Void = { inputs in
            inputs.isPresented = false
            inputs.face = Face(id: 1, words: words)
        }
        let run = try await run(from: away) { inputs in
            withAnimation(.easeInOut(duration: 0.3)) { inputs.isPresented = true }
        } until: { _, _ in
            ContinuousClock.now > end
        }
        // Away, the button is at its low place; risen, at its gap above the key.
        let low = run.rest.floating.maxY
        let risen = try #require(run.samples.last)
        let gap = try #require(risen.gap, "the key never came in")
        #expect(abs(gap - PrimaryKeyButtonStyle.floatingGap) < 0.5, "it never rose: \(risen)")
        #expect(run.samples.contains { $0.key.map { $0.minY - gap > low } ?? false })
        for sample in run.samples {
            guard let key = sample.key else { continue }
            let expected = min(key.minY - gap, low)
            #expect(abs(sample.floating.maxY - expected) < 1, "the two parted: \(sample)")
        }
    }

    /// With Reduce Motion a swap fades the keys in place, and a key taken away fades out as the
    /// button fades from its place above the key into its low one.
    @Test("With Reduce Motion, a swap and a key taken away move nothing")
    func reduceMotionMovesNothing() async throws {
        try Self.setReduceMotion(true)
        defer { try? Self.setReduceMotion(false) }
        #expect(UIAccessibility.isReduceMotionEnabled, "Reduce Motion didn't turn on")
        let swap = try await run({ $0.face = Face(id: 2, words: "Skip rest") }, until: Self.risen)
        let restKey = try #require(swap.rest.key)
        #expect(swap.samples.contains { $0.isOut }, "the keys never swapped")
        for sample in swap.samples {
            #expect(sample.key.map { $0 == restKey } ?? true, "the key moved: \(sample)")
            #expect(sample.floating == swap.rest.floating, "the button moved: \(sample)")
        }
        let end = ContinuousClock.now + .seconds(3 * PrimaryKeyButtonStyle.swapHalf)
        let away = try await run { inputs in
            withAnimation(.easeInOut(duration: 0.3)) { inputs.isPresented = false }
        } until: { _, _ in
            ContinuousClock.now > end
        }
        let high = away.rest.floating.maxY
        let low = try #require(away.rest.key).maxY
        for sample in away.samples {
            let bottom = sample.floating.maxY
            #expect(abs(bottom - high) < 0.5 || abs(bottom - low) < 0.5, "it moved: \(sample)")
        }
        #expect(abs((away.samples.last?.floating.maxY ?? 0) - low) < 0.5, "it never went low")
    }

    /// The device's Reduce Motion, which SwiftUI's environment follows; no view can set it.
    private static func setReduceMotion(_ enabled: Bool) throws {
        typealias SetEnabled = @convention(c) (Bool) -> Void
        let symbol = try #require(
            dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW)
                .flatMap { dlsym($0, "_AXSSetReduceMotionEnabled") },
            "libAccessibility has no switch for Reduce Motion",
        )
        unsafeBitCast(symbol, to: SetEnabled.self)(enabled)
        NotificationCenter.default.post(
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil,
        )
        RunLoop.main.run(mode: .default, before: .now + 0.05)
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
