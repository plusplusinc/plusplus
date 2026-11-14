// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// How the bar swaps its key on its own, read from the first layouts after a change, as
/// automation reads the key. No real time is waited on: each swap's halves run 0.2 s, and these
/// read only what the bar draws before them.
extension PrimaryKeyBarTests {
    fileprivate struct Face: Equatable, Identifiable {
        let id: Int
        let words: String
    }

    /// What the screen gives the bar, changed by each test after the first layout.
    @Observable
    fileprivate final class Inputs {
        var isPresented = true
        var face = Face(id: 1, words: "Log set")
        var drop: CGFloat = 0
    }

    fileprivate struct SwapHost: View {
        let inputs: Inputs

        var body: some View {
            Color.clear
                .primaryKeyBar(
                    isPresented: inputs.isPresented,
                    face: inputs.face,
                    keepsRoom: true,
                    drop: inputs.drop,
                ) { face in
                    Button(face.words) { }
                }
        }
    }

    /// The bar hosted in a window on `face`, laid out once.
    fileprivate struct Hosted {
        let inputs = Inputs()
        let host: UIHostingController<SwapHost>
        let window: UIWindow

        init(face: Face = Face(id: 1, words: "Log set")) {
            inputs.face = face
            host = UIHostingController(rootView: SwapHost(inputs: inputs))
            window = UIWindow.sceneless(hosting: host, at: .large)
            window.settle()
        }

        /// The key as automation reads it: its words and where it is.
        var keys: [(label: String, frame: CGRect)] {
            AccessibilityTree.leaves(under: host.view).compactMap { leaf in
                leaf.accessibilityLabel.map { ($0, leaf.accessibilityFrame) }
            }
        }

        /// Lets the last change reach one layout, and no more.
        func layOutOnce() {
            window.layoutIfNeeded()
            RunLoop.main.run(mode: .default, before: .now)
        }
    }

    @Test("A key that becomes another kind keeps its words in the first layout after")
    func otherKindKeepsWords() async throws {
        try await AccessibilityTree.whileOn {
            let bar = Hosted()
            defer { bar.window.isHidden = true }
            bar.inputs.face = Face(id: 2, words: "Finish workout")
            bar.window.settle()
            #expect(bar.keys.map(\.label) == ["Log set"])
        }
    }

    @Test("Within a kind, the key's words change at once")
    func sameKindChangesWords() async throws {
        try await AccessibilityTree.whileOn {
            let bar = Hosted()
            defer { bar.window.isHidden = true }
            bar.inputs.face = Face(id: 1, words: "Log right")
            bar.window.settle()
            #expect(bar.keys.map(\.label) == ["Log right"])
        }
    }

    @Test("A key that changed kind while away comes back as the new one")
    func awayComesBackNew() async throws {
        try await AccessibilityTree.whileOn {
            let bar = Hosted()
            defer { bar.window.isHidden = true }
            bar.inputs.isPresented = false
            bar.window.settle()
            bar.inputs.face = Face(id: 2, words: "Finish workout")
            bar.window.settle()
            bar.inputs.isPresented = true
            bar.window.settle()
            #expect(bar.keys.map(\.label) == ["Finish workout"])
        }
    }

    /// Start's return, as the screen plays it: Start ridden down out of sight; then, with no
    /// animation, away with its room kept and the face the workout's key; then, on a later turn,
    /// back under the return's animation. Away and back fall within one update, so the bar's
    /// reactions run only after it draws the key back. Kept by the bar from before, the stage
    /// drew Start in that update and the reaction then changed it to Log set unanimated: on the
    /// phone, Log set appeared at rest in one frame (2026-11-13).
    @Test("A key ridden out of sight comes back as the new kind, rising, in its first layout")
    func droppedComesBackRising() async throws {
        try await AccessibilityTree.whileOn {
            let bar = Hosted(face: Face(id: 0, words: "Start"))
            defer { bar.window.isHidden = true }
            let rest = try #require(bar.keys.first).frame
            withTransaction(\.disablesAnimations, true) { bar.inputs.drop = 600 }
            bar.window.settle()
            withTransaction(\.disablesAnimations, true) {
                bar.inputs.isPresented = false
                bar.inputs.face = Face(id: 1, words: "Log set")
                bar.inputs.drop = 0
            }
            withAnimation(.smooth(duration: 0.2)) { bar.inputs.isPresented = true }
            bar.layOutOnce()
            let back = bar.keys
            #expect(back.map(\.label) == ["Log set"])
            let first = try #require(back.first).frame
            #expect(first.minY > rest.minY, "the key came back at rest, not rising")
        }
    }
}

#endif
