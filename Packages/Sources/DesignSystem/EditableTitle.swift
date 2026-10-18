import SwiftUI

/// A screen title that is edited in place.
///
/// At rest it reads as a title with a faint trailing `_`. Tapping it focuses the field: the `_`
/// becomes the blinking cursor and the keyboard rises. The `_` marks the insertion point
/// wherever it is, under the character that typing will push along, or after the last one. The
/// system caret is hidden, so the `_` is the only cursor there is; a range selection shows the
/// system highlight instead.
///
/// An empty `text` is an unnamed title, which shows its suggestion in its place, in white, or
/// with none the placeholder, in gray. The placeholder is never the field's contents: tapping it
/// puts the `_` under its first letter, typing replaces it, and ending with nothing keeps it. A
/// suggestion opens as text to edit, the caret at its end; committed unchanged it stays a
/// suggestion (`text` stays empty), changed it becomes the title, and cleared the title is
/// unnamed again.
///
/// The suggestion may change at any time. When it does, the old title fades out and the new one
/// types in, each letter shuffling briefly through the name's other letters in blue just behind
/// the lead, then easing to its own color, while the `_` breathes in the rail's joining blue.
/// Reduce Motion crossfades it instead, with no blue, and editing stops it at once.
///
/// The field is a `UITextView` (`TitleTextView`), which draws its own text, so everything the
/// keyboard shows in it (suggestions, inline predictions, text being composed) shows as in any
/// field. The `_` sits where the text system draws its caret, so it is under the right
/// character whatever the name holds, emoji and CJK included. The placeholder or a suggestion
/// is laid out by a second text view set up as the field is, so it wraps as the field would.
public struct EditableTitle: View {
    @Binding private var text: String
    /// Whether the field has focus: set by a tap, by the field as it starts and ends editing,
    /// and by the caller, which ends an edit by setting it false.
    @Binding private var isEditing: Bool
    private let placeholder: String
    private let suggestion: String?
    private let label: LocalizedStringResource
    private let hint: LocalizedStringResource

    @State private var draft: String
    /// What an unnamed title shows as drawn: behind `restingTitle` while a new one types in.
    @State private var shownTitle: String
    @State private var shownOpacity = 1.0
    /// When `shownTitle` started typing in, while it is. The one clock every character's
    /// appearing and landing is read from.
    @State private var typingStart: Date?
    /// The suggestion an edit started from, so committing it unchanged leaves it a suggestion.
    @State private var editedSuggestion: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    public init(
        text: Binding<String>,
        isEditing: Binding<Bool>,
        placeholder: String,
        suggestion: String? = nil,
        accessibilityLabel: LocalizedStringResource,
        accessibilityHint: LocalizedStringResource,
    ) {
        _text = text
        _isEditing = isEditing
        self.placeholder = placeholder
        self.suggestion = suggestion
        label = accessibilityLabel
        hint = accessibilityHint
        _draft = State(initialValue: text.wrappedValue)
        _shownTitle = State(initialValue: suggestion ?? placeholder)
    }

    /// What an unnamed title shows once nothing is typing in.
    private var restingTitle: String {
        suggestion ?? placeholder
    }

    /// Whether `shownTitle` is a suggestion, drawn white, rather than the placeholder, gray. A
    /// suggestion is never the placeholder's text.
    private var shownIsSuggested: Bool {
        shownTitle != placeholder
    }

    /// What the field inserts for a change that types or pastes `replacement`, and whether
    /// editing ends. A newline at its end and nowhere else is a Return, which ends editing and
    /// inserts the rest without it (autocorrect can send a word with it). Any other newline came
    /// from pasted lines and becomes a space, since a title is one paragraph.
    static func newlineEdit(_ replacement: String) -> (insert: String, endsEditing: Bool) {
        if replacement.last?.isNewline == true,
           !replacement.dropLast().contains(where: \.isNewline)
        {
            return (String(replacement.dropLast()), true)
        }
        return (String(replacement.map { $0.isNewline ? " " : $0 }), false)
    }

    /// The title an edit leaves behind: trimmed, and empty, which leaves the title unnamed, when
    /// nothing is left or it is the suggestion the edit started from, unchanged.
    public static func committed(_ draft: String, from suggestion: String? = nil) -> String {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == suggestion ? "" : trimmed
    }

    public var body: some View {
        // Paused rather than added and removed, so the field inside keeps its identity, and its
        // focus, as typing in starts and stops.
        TimelineView(.animation(paused: typingStart == nil)) { context in
            let frame = typingStart.map {
                Self.typingFrame(of: shownTitle, at: context.date.timeIntervalSince($0))
            }
            EditableTitleContent(
                draft: $draft,
                isFocused: $isEditing,
                placeholder: restingTitle,
                shownPlaceholder: frame?.shown ?? shownTitle,
                isSuggested: shownIsSuggested,
                placeholderOpacity: shownOpacity,
                standIns: frame?.standIns ?? [:],
                tints: frame?.tints ?? [:],
                // Blue from the moment a suggestion changes, through the old one's fade and the
                // typing, until the last letter has eased to its own color.
                cursorTint: reduceMotion
                    ? 0
                    : max(
                        suggestion != nil && shownTitle != restingTitle ? 1 : 0,
                        frame?.cursorTint ?? 0,
                    ),
                isEditing: isEditing,
                blinks: true,
                accessibilityLabel: label,
                accessibilityHint: hint,
            )
        }
        // The field is only as tall as its text. Behind it, a target at least 44pt tall reaches
        // down past a short title (above, the navigation bar takes the taps), and a tap there
        // focuses the field as a tap on the text does. A background takes no layout space, so
        // callers space the title like any other text.
        .background(alignment: .top) {
            Color.clear
                .frame(minHeight: ScreenTitle.touchTarget)
                .contentShape(.rect)
                .onTapGesture { isEditing = true }
        }
        .task(id: restingTitle) {
            await showRestingTitle()
        }
        .onChange(of: isEditing) { _, editing in
            if editing {
                // Editing wins over a title typing in, and opens on the final one.
                settle()
                if draft.isEmpty, let suggestion {
                    editedSuggestion = suggestion
                }
                // A suggestion opens as text to edit, the caret at its end, where the field
                // puts it as editing starts.
                draft = editedSuggestion ?? draft
            } else {
                commit()
            }
        }
        .onChange(of: text) { _, newText in
            if !isEditing {
                draft = newText
            }
        }
        .hotReloadable()
    }

    /// Brings the drawn title to the resting one: a suggestion typed in at rest, the placeholder
    /// or anything with Reduce Motion crossfaded, and at once where it can't be seen or the title
    /// is being edited. A newer one cancels this and starts over.
    private func showRestingTitle() async {
        guard shownTitle != restingTitle else { return }
        // Only a suggestion types in. Going back to the placeholder, or with Reduce Motion, it
        // crossfades.
        let crossfades = reduceMotion || suggestion == nil
        guard !crossfades, !isEditing, draft.isEmpty else {
            withAnimation(crossfades ? .snappy(duration: SuggestionTiming.crossfade) : nil) {
                settle()
            }
            return
        }
        typingStart = nil
        withAnimation(.snappy(duration: SuggestionTiming.fadeOut)) {
            shownOpacity = 0
        }
        guard await pause(.seconds(SuggestionTiming.fadeOut)) else { return }
        settle()
        typingStart = .now
        guard await pause(.seconds(Self.typingDuration(of: shownTitle))) else { return }
        typingStart = nil
    }

    /// Waits, and says whether typing in should go on: not cancelled by a newer title, and
    /// not stopped by editing, which has already settled the title.
    private func pause(_ duration: Duration) async -> Bool {
        await (try? Task.sleep(for: duration)) != nil && !isEditing
    }

    /// The resting title as it is, with nothing typing in.
    private func settle() {
        shownTitle = restingTitle
        shownOpacity = 1
        typingStart = nil
    }

    private func commit() {
        text = Self.committed(draft, from: editedSuggestion)
        editedSuggestion = nil
        draft = text
    }
}

#Preview {
    @Previewable @State var name = ""
    @Previewable @State var isEditing = false
    EditableTitle(
        text: $name,
        isEditing: $isEditing,
        placeholder: "New routine",
        accessibilityLabel: "Routine name",
        accessibilityHint: "Renames the routine.",
    )
    .padding()
    .background(Color.pp(.background))
}
