// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// A key taken away and presented again, as another kind, while the one going is still on its
/// way down, as Skip rest between two sets plays it: read frame by frame over real time.
extension PrimaryKeyBarTests {
    fileprivate struct Face: Equatable, Identifiable {
        let id: Int
        let words: String
    }

    @Observable
    fileprivate final class ReturnInputs {
        var isPresented = true
        var face = Face(id: 1, words: "Skip rest")
    }

    fileprivate struct ReturnHost: View {
        let inputs: ReturnInputs

        var body: some View {
            Color.clear
                .primaryKeyBar(
                    isPresented: inputs.isPresented,
                    face: inputs.face,
                    keepsRoom: true,
                ) { face, isOut in
                    Button(face.words) { }
                        .accessibilityValue(isOut ? "out" : "")
                }
        }
    }

    /// Put back as the key going, the new kind came back up as the old one, then swapped: down
    /// and up a second time (2026-11-25).
    @Test("A key presented again as another kind mid-leave turns back up once, as the new kind")
    func returnMidLeaveRisesOnce() async throws {
        try await AccessibilityTree.whileOn {
            let inputs = ReturnInputs()
            let host = UIHostingController(rootView: ReturnHost(inputs: inputs))
            let window = UIWindow.sceneless(hosting: host, at: .large)
            defer { window.isHidden = true }
            window.settle()
            let leaves = { AccessibilityTree.leaves(under: host.view) }
            let rest = try #require(leaves().first { $0.accessibilityLabel == "Skip rest" })
                .accessibilityFrame
            withAnimation(.easeInOut(duration: 0.3)) {
                inputs.isPresented = false
                inputs.face = Face(id: 2, words: "Log set")
            }
            // Partway down, as Skip rest's hold ends inside its keys' drop.
            let back = ContinuousClock.now + .seconds(0.15)
            while ContinuousClock.now < back {
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(4))
            }
            // Still on its way, which automation can't read: a key taken away leaves the tree.
            // Past the drop's end, the test would test nothing.
            #expect(
                ContinuousClock.now < back + .seconds(0.1),
                "the drop was over before the return",
            )
            withAnimation(.easeInOut(duration: 0.3)) { inputs.isPresented = true }
            // Where the one key is drawn, sample by sample: from the return on, the new kind,
            // only rising, never out in a swap.
            var tops: [CGFloat] = []
            let limit = ContinuousClock.now + .seconds(10 * PrimaryKeyButtonStyle.swapHalf)
            while ContinuousClock.now < limit {
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(4))
                // Labeled only: the host's `Color.clear` is an unlabeled leaf of no size.
                let keys = leaves().filter { $0.accessibilityLabel != nil }
                #expect(keys.count <= 1, "two keys at once: \(keys.map(\.accessibilityLabel))")
                for key in keys {
                    #expect(key.accessibilityValue != "out", "the key swapped on its way up")
                    #expect(key.accessibilityLabel == "Log set", "it rose as the key going")
                    tops.append(key.accessibilityFrame.minY)
                }
                if let top = tops.last, abs(top - rest.minY) < 0.5 {
                    break
                }
            }
            #expect(abs((tops.last ?? .infinity) - rest.minY) < 0.5, "it never rose: \(tops)")
            // One turn: on down as far as the leave carries it, then only up.
            let lowest = tops.indices.max { tops[$0] < tops[$1] } ?? 0
            let down = tops[...lowest]
            let up = tops[lowest...]
            #expect(zip(down, down.dropFirst()).allSatisfy { $1 >= $0 }, "came back: \(tops)")
            #expect(zip(up, up.dropFirst()).allSatisfy { $1 <= $0 }, "went down again: \(tops)")
        }
    }
}

#endif
