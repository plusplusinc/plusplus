// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// An unnamed title whose resting text changes and changes back while the old one is still
/// fading out, as adding an exercise and deleting it at once does: the run for the new text is
/// cancelled before it shows anything, and the title has to come back. Read from a hosted view,
/// with the order forced: the change back is made only once the fade-out is seen to be under way.
@MainActor
@Suite("Editable title changed and changed back")
struct EditableTitleChangeBackTests {
    @Observable
    final class Model {
        var suggestion: String?

        init(suggestion: String?) {
            self.suggestion = suggestion
        }
    }

    private struct Host: View {
        let model: Model
        @State private var name = ""
        @State private var isEditing = false

        var body: some View {
            EditableTitle(
                text: $name,
                isEditing: $isEditing,
                placeholder: "New routine",
                suggestion: model.suggestion,
                accessibilityLabel: "Routine name",
                accessibilityHint: "Renames the routine.",
            )
            .frame(width: 370)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Turns the run loop until `done` holds or `limit` seconds have passed.
    private func wait(in window: UIWindow, upTo limit: TimeInterval, until done: () -> Bool) {
        let deadline = Date.now.addingTimeInterval(limit)
        while !done(), Date.now < deadline {
            window.layoutIfNeeded()
            RunLoop.main.run(mode: .default, before: .now.addingTimeInterval(0.01))
        }
    }

    /// From the placeholder to a suggestion and back, as a new routine's first exercise added
    /// and deleted, and from one suggestion to another and back.
    @Test(
        "A title changed and changed back inside the fade-out shows again, whole",
        arguments: [nil, "Push"] as [String?],
    )
    func changedBack(first: String?) throws {
        let model = Model(suggestion: first)
        let host = UIHostingController(rootView: Host(model: model))
        host.safeAreaRegions = []
        let window = UIWindow.sceneless(hosting: host, at: .large)
        defer { window.isHidden = true }
        window.settle()
        func field(in view: UIView) -> TitleFieldView? {
            view as? TitleFieldView ?? view.subviews.lazy.compactMap(field(in:)).first
        }
        let drawn = try #require(field(in: host.view)).placeholderView
        let resting = first ?? "New routine"
        try #require(drawn.text == resting && drawn.alpha == 1)
        // A title at rest is left alone: showing it starts no fade.
        #expect(drawn.layer.animationKeys() ?? [] == [])

        model.suggestion = "Pull"
        wait(in: window, upTo: 1) { drawn.alpha == 0 }
        // The order this is about: the old title fading out, the new one not yet drawn.
        try #require(drawn.alpha == 0 && drawn.text == resting, "the fade-out never started")

        model.suggestion = first
        wait(in: window, upTo: 1) { drawn.alpha == 1 }
        #expect(drawn.alpha == 1, "the title stayed faded out")
        #expect(drawn.text == resting)

        // Past the cancelled run's wait, nothing it left goes on: no fade, no typing.
        wait(in: window, upTo: SuggestionTiming.fadeOut * 2) { false }
        #expect(drawn.alpha == 1)
        #expect(drawn.text == resting)
    }
}

#endif
