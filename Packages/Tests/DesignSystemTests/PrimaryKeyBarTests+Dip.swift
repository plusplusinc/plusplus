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
                ) { face, _ in
                    Button(face.words) { }
                } floating: {
                    Button("Add exercise", systemImage: "plus") { }
                }
        }
    }

    /// How far the key and the floating button are drawn below where they rest, sampled over a
    /// swap; the key's is nil while none is drawn.
    fileprivate struct Sample {
        let key: CGFloat?
        let floating: CGFloat
    }

    /// Hosts the bar on Log set, changes it by `change`, and samples it until well past the
    /// swap's two halves.
    private func samples(_ change: (DipInputs) -> Void) async throws -> [Sample] {
        try await AccessibilityTree.whileOn {
            let inputs = DipInputs()
            let host = UIHostingController(rootView: DipHost(inputs: inputs))
            let window = UIWindow.sceneless(hosting: host, at: .large)
            defer { window.isHidden = true }
            window.settle()
            @MainActor func frames() -> (key: CGRect?, floating: CGRect?) {
                let leaves = AccessibilityTree.leaves(under: host.view)
                let floating = leaves.first { $0.accessibilityLabel == "Add exercise" }
                let key = leaves
                    .first {
                        $0.accessibilityLabel != "Add exercise" && $0.accessibilityLabel != nil
                    }
                return (key?.accessibilityFrame, floating?.accessibilityFrame)
            }
            let rest = frames()
            let keyRest = try #require(rest.key).minY
            let floatingRest = try #require(rest.floating).minY
            change(inputs)
            var samples: [Sample] = []
            let deadline = Date.now.addingTimeInterval(4 * PrimaryKeyButtonStyle.swapHalf + 0.4)
            while Date.now < deadline {
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(4))
                let now = frames()
                let floating = try #require(now.floating, "the floating button went from the tree")
                samples.append(Sample(
                    key: now.key.map { $0.minY - keyRest },
                    floating: floating.minY - floatingRest,
                ))
            }
            return samples
        }
    }

    @Test("Through a swap, the floating button goes down and back up with the keys, as one piece")
    func floatingDipsWithSwap() async throws {
        let samples = try await samples { $0.face = Face(id: 2, words: "Skip rest") }
        let deepest = try #require(samples.map(\.floating).max())
        #expect(deepest > 40, "the floating button never went down: \(deepest)")
        for sample in samples {
            guard let key = sample.key else { continue }
            #expect(abs(key - sample.floating) < 1, "the button and the key parted: \(sample)")
        }
        let last = try #require(samples.last)
        #expect(last.key == 0 && last.floating == 0, "they didn't come back where they began")
    }

    /// As a key leaves with none to follow, the screen sets the button low on the same update:
    /// it goes down once and stays, rather than dipping with the swap and coming back up first.
    @Test("Going low as the key swaps, the floating button only goes down")
    func floatingGoesLowOnce() async throws {
        let samples = try await samples { inputs in
            withAnimation(.easeInOut(duration: 0.3)) {
                inputs.face = Face(id: 2, words: "Skip rest")
                inputs.floatsLow = true
            }
        }
        let path = samples.map(\.floating)
        #expect(zip(path, path.dropFirst()).allSatisfy { $1 >= $0 }, "it went back up: \(path)")
        #expect((path.last ?? 0) > 40, "it never went low: \(path)")
    }

    @Test("Within a kind, the floating button stays put as the words change")
    func floatingStillWithinKind() async throws {
        let samples = try await samples { $0.face = Face(id: 1, words: "Log right") }
        #expect(samples.allSatisfy { $0.floating == 0 }, "the button moved")
    }
}

#endif
