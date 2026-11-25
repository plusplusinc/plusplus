// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// The title hands each change on as it is typed, by the rule `committed(_:from:)` holds, so a
/// name is kept however the edit is left, including ways that end no edit: the app leaving the
/// foreground, or the screen going away.
@MainActor
@Suite("Editable title hands on what is typed while the edit is open")
struct EditableTitleTypingTests {
    /// Every value the title handed on.
    private final class Log {
        var names: [String] = []
    }

    private struct Host: View {
        @State var name = ""
        @State var isEditing = false
        let suggestion: String?
        let log: Log

        var body: some View {
            EditableTitle(
                text: $name,
                isEditing: $isEditing,
                placeholder: "New workout",
                suggestion: suggestion,
                accessibilityLabel: "Workout name",
                accessibilityHint: "Renames the workout.",
            )
            .onChange(of: name) { _, name in log.names.append(name) }
            .frame(width: 370)
        }
    }

    /// Starts an edit on a title showing `suggestion`, types `keys` one at a time, and returns
    /// what the title handed on, with the edit still open.
    private func typed(_ keys: [String], over suggestion: String?) throws -> [String] {
        let log = Log()
        let host = UIHostingController(rootView: Host(suggestion: suggestion, log: log))
        let window = UIWindow.sceneless(hosting: host, at: .large)
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        let field = try #require(Self.field(in: host.view))
        window.settle()
        try #require(field.becomeFirstResponder())
        window.settle()
        for key in keys {
            if key.isEmpty {
                field.deleteBackward()
            } else {
                field.insertText(key)
            }
            window.settle()
        }
        try #require(field.isFirstResponder, "The edit ended")
        return log.names
    }

    private static func field(in view: UIView) -> UITextView? {
        view as? UITextView ?? view.subviews.lazy.compactMap(field(in:)).first
    }

    /// A draft that hands the field `shown`, which the test moves on by hand, so an update can
    /// reach the field before the draft has taken what the field set: in the app a SwiftUI
    /// update can read the title's draft a key or two behind the field, as a workout is first
    /// named.
    @Observable
    final class LaggingDraft {
        var shown: String
        /// Changed to make SwiftUI update the field.
        var pass = 0

        init(_ shown: String) {
            self.shown = shown
        }
    }

    private struct LaggingHost: View {
        let draft: LaggingDraft

        var body: some View {
            EditableTitleContent(
                draft: Binding { draft.shown } set: { _ in },
                placeholder: "New workout \(draft.pass)",
                shownPlaceholder: "New workout",
                isEditing: true,
                blinks: false,
                accessibilityLabel: "Workout name",
                accessibilityHint: "Renames the workout.",
            )
            .frame(width: 370)
        }
    }

    @Test("A draft behind the field's typing never puts back what was typed over")
    func laggingDraftKeepsTyping() throws {
        let draft = LaggingDraft("Leg")
        let host = UIHostingController(rootView: LaggingHost(draft: draft))
        let window = UIWindow.sceneless(hosting: host, at: .large)
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        let field = try #require(Self.field(in: host.view))
        window.settle()
        try #require(field.becomeFirstResponder())
        window.settle()
        field.deleteBackward()
        field.deleteBackward()
        // An update with the draft still at a text the field has typed past.
        draft.pass += 1
        window.settle()
        #expect(field.text == "L", "An update put a text typed over back in the field")
        draft.shown = "Le"
        draft.pass += 1
        window.settle()
        #expect(field.text == "L", "An update put a text typed over back in the field")
        // A text the field never held still reaches it.
        draft.shown = "Arm"
        window.settle()
        #expect(field.text == "Arm", "The draft no longer reaches the field")
    }

    @Test("Each letter typed reaches the title before the edit ends")
    func typedLettersReachTheTitle() throws {
        #expect(try typed(["L", "e", "g"], over: nil) == ["L", "Le", "Leg"])
    }

    @Test("A suggestion opened and cleared hands on nothing, leaving the title unnamed")
    func clearedSuggestionStaysUnnamed() throws {
        // Deleting from the suggestion's end names the title for a moment, then leaves it
        // unnamed again once nothing is left.
        let names = try typed(["", "", ""], over: "Leg")
        #expect(names == ["Le", "L", ""])
    }

    @Test("Typing a suggestion back as it was leaves the title unnamed")
    func suggestionRetypedStaysUnnamed() throws {
        #expect(try typed(["", "g"], over: "Leg") == ["Le", ""])
    }
}

#endif
