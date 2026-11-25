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
        let (window, field) = try focused(Host(suggestion: suggestion, log: log))
        defer { window.isHidden = true }
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

    /// A window showing `root`, and its title's field, focused. The caller hides the window.
    private func focused(_ root: some View) throws -> (UIWindow, UITextView) {
        func field(in view: UIView) -> UITextView? {
            view as? UITextView ?? view.subviews.lazy.compactMap(field(in:)).first
        }
        let host = UIHostingController(rootView: root)
        let window = UIWindow.sceneless(hosting: host, at: .large)
        window.layoutIfNeeded()
        let field = try #require(field(in: host.view))
        window.settle()
        try #require(field.becomeFirstResponder())
        window.settle()
        return (window, field)
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
        let (window, field) = try focused(LaggingHost(draft: draft))
        defer { window.isHidden = true }
        field.deleteBackward()
        field.deleteBackward()
        // An update with the draft still at a text the field has typed past.
        draft.pass += 1
        window.settle()
        #expect(field.text == "L", "An update put a text typed over back in the field")
        draft.shown = "Le"
        window.settle()
        #expect(field.text == "L", "An update put a text typed over back in the field")
        // Caught up, and then a read from before that.
        draft.shown = "L"
        window.settle()
        draft.shown = "Leg"
        window.settle()
        #expect(field.text == "L", "An update put a text typed over back in the field")
        // A text the field never held still reaches it.
        draft.shown = "Arm"
        window.settle()
        #expect(field.text == "Arm", "The draft no longer reaches the field")
    }

    @Test("A name trimmed as the edit ends reaches the field, though the field held it earlier")
    func trimmedNameReachesTheField() throws {
        let (window, field) = try focused(Host(suggestion: nil, log: Log()))
        defer { window.isHidden = true }
        for key in ["L", "e", "g", " "] {
            field.insertText(key)
            window.settle()
        }
        try #require(field.text == "Leg ")
        try #require(field.resignFirstResponder())
        window.settle()
        #expect(field.text == "Leg", "The field kept the untrimmed text after the edit ended")
    }

    @Test("A suggestion cleared in one edit opens as text again in the next")
    func suggestionOpensAgainInTheNextEdit() throws {
        let (window, field) = try focused(Host(suggestion: "Leg", log: Log()))
        defer { window.isHidden = true }
        try #require(field.text == "Leg")
        for _ in 0 ..< 3 {
            field.deleteBackward()
            window.settle()
        }
        try #require(field.resignFirstResponder())
        window.settle()
        try #require(field.text.isEmpty)
        try #require(field.becomeFirstResponder())
        window.settle()
        #expect(field.text == "Leg", "The suggestion didn't open, a text the last edit held")
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
