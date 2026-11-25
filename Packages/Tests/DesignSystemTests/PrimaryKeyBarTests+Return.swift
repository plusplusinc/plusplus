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
    @Test("A key presented again as another kind mid-leave rises once, with no swap")
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
            // Still on its way, which automation can't read: a removed view leaves the tree.
            // Past the drop's end, the test would test nothing.
            #expect(
                ContinuousClock.now < back + .seconds(0.1),
                "the drop was over before the return",
            )
            withAnimation(.easeInOut(duration: 0.3)) { inputs.isPresented = true }
            // Where each key is drawn, sample by sample: the one going, back in the tree only if
            // revived, never comes back up, and the one coming only rises, neither ever out in
            // a swap.
            var going: [CGFloat] = []
            var coming: [CGFloat] = []
            let limit = ContinuousClock.now + .seconds(10 * PrimaryKeyButtonStyle.swapHalf)
            while ContinuousClock.now < limit {
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(4))
                for key in leaves() {
                    #expect(key.accessibilityValue != "out", "the key swapped on its way up")
                    let top = key.accessibilityFrame.minY
                    if key.accessibilityLabel == "Skip rest" {
                        going.append(top)
                    } else if key.accessibilityLabel == "Log set" {
                        coming.append(top)
                    }
                }
                if let top = coming.last, abs(top - rest.minY) < 0.5 {
                    break
                }
            }
            #expect(abs((coming.last ?? .infinity) - rest.minY) < 0.5, "it never rose: \(coming)")
            #expect(zip(going, going.dropFirst()).allSatisfy { $1 >= $0 }, "came back: \(going)")
            #expect(zip(coming, coming.dropFirst()).allSatisfy { $1 <= $0 }, "went down: \(coming)")
        }
    }
}

#endif
