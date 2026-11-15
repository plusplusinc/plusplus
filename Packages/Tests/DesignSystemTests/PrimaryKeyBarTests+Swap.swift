// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// How the bar swaps its key on its own, read from the first layouts after a change, as
/// automation reads the key. No real time is waited on: each half of a swap runs
/// `PrimaryKeyButtonStyle.swapHalf`, and these read only what the bar draws before it.
extension PrimaryKeyBarTests {
    fileprivate struct Face: Equatable, Identifiable {
        let id: Int
        let words: String
    }

    /// What the screen gives the bar, changed by each test after the first layout.
    @Observable
    fileprivate final class Inputs {
        var isPresented = true
        var face: Face
        var drop: CGFloat = 0

        init(face: Face) {
            self.face = face
        }
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
                ) { face, isOut in
                    // What the bar tells the key, where the tests can read it.
                    Button(face.words) { }
                        .accessibilityValue(isOut ? "out" : "")
                }
        }
    }

    /// The bar hosted in a window on a face, laid out once, with the accessibility tree on.
    fileprivate struct Hosted {
        let inputs: Inputs
        let host: UIHostingController<SwapHost>
        let window: UIWindow

        /// Runs `test` on the bar hosted on `face`, then takes the window down.
        static func on(
            _ face: Face = Face(id: 1, words: "Log set"),
            _ test: (Self) throws -> Void,
        ) throws {
            try AccessibilityTree.whileOn {
                let bar = Self(face: face)
                defer { bar.window.isHidden = true }
                try test(bar)
            }
        }

        private init(face: Face) {
            inputs = Inputs(face: face)
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

        /// The key's one node in the tree.
        var leaf: NSObject? {
            AccessibilityTree.leaves(under: host.view).first { $0.accessibilityLabel != nil }
        }

        /// Lets the last change reach one layout, and no more.
        func layOutOnce() {
            window.layoutIfNeeded()
            RunLoop.main.run(mode: .default, before: .now)
        }
    }

    @Test("A key that becomes another kind keeps its words in the first layout after")
    func otherKindKeepsWords() throws {
        try Hosted.on { bar in
            bar.inputs.face = Face(id: 2, words: "Finish workout")
            // One layout, well inside the swap's first half on a loaded machine.
            bar.layOutOnce()
            #expect(bar.keys.map(\.label) == ["Log set"])
        }
    }

    /// Disabled while out, the key read as dimmed to VoiceOver for each swap's first half; on
    /// `main` it stayed enabled and the screen dropped the tap. The key's action is what drops it,
    /// told by the bar that the key is out.
    @Test("A leaving key stays enabled, with its words, and is told it is out")
    func leavingStaysEnabled() throws {
        try Hosted.on { bar in
            #expect(bar.leaf?.accessibilityValue != "out")
            bar.inputs.face = Face(id: 2, words: "Finish workout")
            bar.layOutOnce()
            let leaf = try #require(bar.leaf)
            #expect(leaf.accessibilityLabel == "Log set")
            #expect(leaf.accessibilityValue == "out")
            #expect(!leaf.accessibilityTraits.contains(.notEnabled), "the key went dimmed")
        }
    }

    @Test("Within a kind, the key's words change at once")
    func sameKindChangesWords() throws {
        try Hosted.on { bar in
            bar.inputs.face = Face(id: 1, words: "Log right")
            bar.window.settle()
            #expect(bar.keys.map(\.label) == ["Log right"])
        }
    }

    @Test("A key that changed kind while away comes back as the new one")
    func awayComesBackNew() throws {
        try Hosted.on { bar in
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
    /// animation, away with its room kept and the face the workout's key; then back under the
    /// return's animation. In the app, the key came back before the bar's reactions ran, with
    /// the state it had before it went (logged 2026-11-13), which this forces by bringing it
    /// back with no layout between. Drawn from that state, the key came back as Start and the
    /// reaction then changed it to Log set unanimated: on the phone, Log set appeared at rest in
    /// one frame.
    @Test("A key ridden out of sight comes back as the new kind, rising, in its first layout")
    func droppedComesBackRising() throws {
        try Hosted.on(Face(id: 0, words: "Start")) { bar in
            let rest = try #require(bar.keys.first).frame
            withTransaction(\.disablesAnimations, true) { bar.inputs.drop = 600 }
            bar.window.settle()
            withTransaction(\.disablesAnimations, true) {
                bar.inputs.isPresented = false
                bar.inputs.face = Face(id: 1, words: "Log set")
                bar.inputs.drop = 0
            }
            withAnimation(.smooth(duration: PrimaryKeyButtonStyle.swapHalf)) {
                bar.inputs.isPresented = true
            }
            bar.layOutOnce()
            let back = bar.keys
            #expect(back.map(\.label) == ["Log set"])
            let first = try #require(back.first).frame
            #expect(first.minY > rest.minY, "the key came back at rest, not rising")
        }
    }
}

#endif
