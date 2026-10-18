#if os(iOS)
import SwiftUI
import UIKit

/// The title's field: a `UITextView`, with the placeholder and the `_` as subviews.
///
/// UIKit rather than SwiftUI's `TextField`, for two things the text system knows and SwiftUI
/// does not say: where each character is drawn, which places the `_` under the one after the
/// caret, however wide it is; and Return, which arrives here as a change the field can
/// refuse, so a newline never reaches the draft and never adds a line for a moment.
///
/// One text view, never swapped, sized in `sizeThatFits` from its own layout: what it shows,
/// the draft or the placeholder, at the width offered. Focus changes nothing that sizes it.
/// Everything it draws arrives as plain values worked out in SwiftUI.
struct TitleTextView: UIViewRepresentable {
    @Binding var draft: String
    /// Nil where nothing takes focus, as in a snapshot.
    var isFocused: Binding<Bool>?
    /// How the title looks: editing, or at rest.
    let isEditing: Bool
    /// A selection to force, for a snapshot; nil leaves it to the text view.
    var selection: NSRange?
    let fontSize: CGFloat
    /// How far the `_` sits below the top of its line's own underscore.
    let drop: CGFloat
    /// What an empty field shows, as drawn, with a color for each character.
    let placeholder: String
    let placeholderColors: [Color]
    let placeholderOpacity: Double
    let cursorColor: Color
    let cursorOpacity: Double
    /// Whether the `_` blinks while editing.
    let blinks: Bool
    let accessibilityLabel: String
    let accessibilityHint: String
    /// What VoiceOver reads as the value of an empty field.
    let accessibilityPlaceholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> TitleFieldView {
        let view = TitleFieldView()
        view.delegate = context.coordinator
        view.returnKeyType = .done
        view.autocapitalizationType = .sentences
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    func updateUIView(_ view: TitleFieldView, context: Context) {
        context.coordinator.parent = self
        let environment = context.environment
        let font = ScreenTitle.uiFont(ofSize: fontSize)
        let color = Color.pp(.textPrimary).uiColor(in: environment)
        // Only what changes the text's size asks SwiftUI to measure again: the cursor's color
        // and the breath change every frame while a suggestion arrives.
        var resized = view.font != font
        // Written only when they change: each rewrites the whole text's attributes, which
        // would disturb text being composed.
        if resized || view.textColor?.cgColor != color.cgColor {
            view.font = font
            view.textColor = color
            view.typingAttributes = [.font: font, .foregroundColor: color]
            view.placeholderView.font = font
        }
        if view.text != draft, view.markedTextRange == nil {
            view.text = draft
            resized = true
        }

        let shownPlaceholder = view.placeholderView.text
        updatePlaceholder(of: view, font: font, context: context)
        resized = resized || view.placeholderView.text != shownPlaceholder
        context.animate {
            view.placeholderView.alpha = placeholderOpacity
        }

        view.cursorView.font = font
        view.cursorView.textColor = cursorColor.uiColor(in: environment)
        view.cursorView.alpha = cursorOpacity
        view.drop = drop
        view.isEditingLook = isEditing
        view.blinks = blinks

        view.accessibilityLabel = accessibilityLabel
        view.accessibilityHint = accessibilityHint
        view.accessibilityPlaceholder = accessibilityPlaceholder

        if let isFocused {
            if isFocused.wrappedValue, !view.isFirstResponder {
                view.becomeFirstResponder()
            } else if !isFocused.wrappedValue, view.isFirstResponder {
                view.resignFirstResponder()
            }
        }
        if let selection, view.selectedRange != selection {
            view.selectedRange = selection
        }
        view.updateCursor(restartsBlink: false)
        if resized {
            view.invalidateIntrinsicContentSize()
            view.setNeedsLayout()
        }
    }

    /// Draws the placeholder: each character in its own color, crossfaded to new text when the
    /// change is animated (the Reduce Motion crossfade, and the return to the placeholder).
    private func updatePlaceholder(of view: TitleFieldView, font: UIFont, context: Context) {
        let environment = context.environment
        let drawn = NSMutableAttributedString()
        for (character, characterColor) in zip(placeholder, placeholderColors) {
            drawn.append(NSAttributedString(
                string: String(character),
                attributes: [
                    .font: font,
                    .foregroundColor: characterColor.uiColor(in: environment),
                ],
            ))
        }
        if view.placeholderView.attributedText != drawn {
            if context.transaction.animation != nil,
               view.placeholderView.attributedText.string != drawn.string
            {
                UIView.transition(
                    with: view.placeholderView,
                    duration: SuggestionTiming.crossfade,
                    options: .transitionCrossDissolve,
                ) {
                    view.placeholderView.attributedText = drawn
                }
            } else {
                view.placeholderView.attributedText = drawn
            }
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView view: TitleFieldView,
        context: Context,
    ) -> CGSize? {
        let width = proposal.width ?? .greatestFiniteMagnitude
        let size = view.shownTextView.fittingSize(
            width: width,
            scale: context.environment.displayScale,
        )
        return CGSize(width: proposal.width ?? size.width, height: size.height)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: TitleTextView

        init(_ parent: TitleTextView) {
            self.parent = parent
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String,
        ) -> Bool {
            let edit = EditableTitle.newlineEdit(text)
            guard edit.insert != text || edit.endsEditing else { return true }
            if !edit.insert.isEmpty || range.length > 0,
               let start = textView.position(
                   from: textView.beginningOfDocument,
                   offset: range.location,
               ),
               let end = textView.position(from: start, offset: range.length),
               let textRange = textView.textRange(from: start, to: end)
            {
                textView.replace(textRange, withText: edit.insert)
                textViewDidChange(textView)
            }
            if edit.endsEditing {
                textView.resignFirstResponder()
            }
            return false
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let view = textView as? TitleFieldView else { return }
            if parent.draft != view.text {
                parent.draft = view.text
            }
            view.invalidateIntrinsicContentSize()
            view.setNeedsLayout()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            (textView as? TitleFieldView)?.updateCursor(restartsBlink: true)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            // Editing starts at the end of the name.
            let end = textView.endOfDocument
            textView.selectedTextRange = textView.textRange(from: end, to: end)
            if let isFocused = parent.isFocused, !isFocused.wrappedValue {
                isFocused.wrappedValue = true
            }
        }

        func textViewDidEndEditing(_: UITextView) {
            if let isFocused = parent.isFocused, isFocused.wrappedValue {
                isFocused.wrappedValue = false
            }
        }
    }
}

extension Color {
    fileprivate func uiColor(in environment: EnvironmentValues) -> UIColor {
        UIColor(cgColor: resolve(in: environment).cgColor)
    }
}
#endif
