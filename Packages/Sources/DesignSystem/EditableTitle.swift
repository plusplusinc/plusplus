import SwiftUI

/// A screen title that is edited in place.
///
/// At rest it reads as a title with a faint trailing `_`. Tapping it focuses the field: the `_`
/// becomes the blinking cursor and the keyboard rises. The system caret is hidden, so the `_`
/// is the only cursor there is, and it always sits after the last character.
///
/// Editing the default text starts from an empty field showing the default as its prompt, so
/// typing replaces it the way a select-all would. Ending with nothing restores the default.
public struct EditableTitle: View {
    @Binding private var text: String
    private let defaultText: String
    private let label: LocalizedStringKey
    private let hint: LocalizedStringKey

    @State private var draft: String
    @FocusState private var isEditing: Bool
    @ObserveHotReload private var hotReload

    /// Matches the 1.06s cycle of a text cursor: on half, off half, no fade.
    private static let blinkInterval: TimeInterval = 0.53

    public init(
        text: Binding<String>,
        defaultText: String,
        accessibilityLabel: LocalizedStringKey,
        accessibilityHint: LocalizedStringKey,
    ) {
        _text = text
        self.defaultText = defaultText
        label = accessibilityLabel
        hint = accessibilityHint
        _draft = State(initialValue: text.wrappedValue)
    }

    /// What the field holds when editing starts: empty for the default, so typing replaces it.
    public static func draft(forEditing text: String, defaultText: String) -> String {
        text == defaultText ? "" : text
    }

    /// The title an edit leaves behind: trimmed, and the default when nothing is left.
    public static func committed(_ draft: String, defaultText: String) -> String {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultText : trimmed
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            field
            cursor
        }
        .font(.ppScreenTitle)
        // The field is only as tall as its text; the padding makes a 44pt target around it,
        // and a tap there focuses the field just as a tap on the text does.
        .padding(.vertical, Spacing.sm)
        .contentShape(.rect)
        .onTapGesture { isEditing = true }
        .onChange(of: isEditing) { _, editing in
            if editing {
                draft = Self.draft(forEditing: text, defaultText: defaultText)
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

    private var field: some View {
        TextField(
            "",
            text: $draft,
            prompt: Text(defaultText).foregroundStyle(.pp(.textPrimary)),
            axis: .vertical,
        )
        .foregroundStyle(.pp(.textPrimary))
        // The `_` overlay is the cursor; the system caret would be a second one.
        .tint(.clear)
        .focused($isEditing)
        .submitLabel(.done)
        .autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.words)
        #endif
        .onSubmit { isEditing = false }
        // A hardware keyboard's Return reaches a vertical field as a key press.
        .onKeyPress(.return) {
            isEditing = false
            return .handled
        }
        // The on-screen keyboard's Return reaches it as a newline.
        .onChange(of: draft) { _, newDraft in
            guard newDraft.contains(where: \.isNewline) else { return }
            draft = newDraft.filter { !$0.isNewline }
            isEditing = false
        }
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(text))
        .accessibilityHint(Text(hint))
    }

    /// A clear copy of the shown text followed by the `_`, so the `_` wraps with the text and
    /// lands right after its last glyph. A thin space keeps the `_` from tucking under a
    /// letter with an overhang, like a final "e".
    private var cursor: some View {
        TimelineView(.periodic(from: .now, by: Self.blinkInterval)) { context in
            let shown = draft.isEmpty ? defaultText : draft
            let visible = !isEditing || Self.isBlinkOn(at: context.date)
            let mark = Text(verbatim: "\u{2009}_")
                .foregroundStyle(isEditing ? .pp(.textPrimary) : .pp(.borderStrong))
            Text("\(Text(shown).foregroundStyle(.clear))\(mark)")
                .opacity(visible ? 1 : 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func isBlinkOn(at date: Date) -> Bool {
        Int(date.timeIntervalSinceReferenceDate / blinkInterval).isMultiple(of: 2)
    }

    private func commit() {
        text = Self.committed(draft, defaultText: defaultText)
        draft = text
    }
}

#Preview {
    @Previewable @State var name = "New routine"
    EditableTitle(
        text: $name,
        defaultText: "New routine",
        accessibilityLabel: "Routine name",
        accessibilityHint: "Renames the routine.",
    )
    .padding()
    .background(Color.pp(.background))
}
