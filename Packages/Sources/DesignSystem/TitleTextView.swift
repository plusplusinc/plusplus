#if os(iOS)
import SwiftUI
import UIKit

/// The title's field: a `UITextView`, with the placeholder and the `_` as subviews.
///
/// UIKit rather than SwiftUI's `TextField`, for two things the text system knows and SwiftUI
/// does not say: where the caret is drawn, which places the `_` (`caretRect(for:)`), however
/// wide the characters before it are; and Return, which arrives here as a change the field can
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
    let textColor: Color
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
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        let color = textColor.uiColor(in: environment)
        view.font = font
        view.textColor = color
        view.typingAttributes = [.font: font, .foregroundColor: color]
        view.placeholderView.font = font
        if view.text != draft, view.markedTextRange == nil {
            view.text = draft
        }
        view.isEmptyDraft = draft.isEmpty

        updatePlaceholder(of: view, font: font, context: context)
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
        view.invalidateIntrinsicContentSize()
        view.setNeedsLayout()
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
        context _: Context,
    ) -> CGSize? {
        let width = proposal.width ?? .greatestFiniteMagnitude
        let size = view.shownTextView.fittingSize(width: width)
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
            view.isEmptyDraft = view.text.isEmpty
            view.invalidateIntrinsicContentSize()
            view.setNeedsLayout()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            (textView as? TitleFieldView)?.updateCursor(restartsBlink: true)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            // Editing starts at the end, wherever the focusing tap landed.
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

/// The field, with the placeholder under its text and the `_` over it.
final class TitleFieldView: UITextView {
    /// Laid out as the field is, so moving between the two keeps the height when the strings
    /// match.
    let placeholderView = UITextView()
    let cursorView = UILabel()
    var drop: CGFloat = 0
    var isEmptyDraft = true {
        didSet { placeholderView.isHidden = !isEmptyDraft }
    }

    var isEditingLook = false {
        didSet {
            if isEditingLook != oldValue {
                updateCursor(restartsBlink: true)
            }
        }
    }

    var blinks = true
    var accessibilityPlaceholder = ""

    private static let blinkInterval: CFTimeInterval = 0.53
    private static let blinkKey = "blink"

    init() {
        super.init(frame: .zero, textContainer: nil)
        Self.configure(self)
        Self.configure(placeholderView)
        placeholderView.isEditable = false
        placeholderView.isSelectable = false
        placeholderView.isUserInteractionEnabled = false
        placeholderView.isAccessibilityElement = false
        placeholderView.accessibilityElementsHidden = true
        insertSubview(placeholderView, at: 0)

        cursorView.text = "_"
        cursorView.isUserInteractionEnabled = false
        cursorView.isAccessibilityElement = false
        cursorView.accessibilityElementsHidden = true
        addSubview(cursorView)
        // The `_` hangs past the trailing edge after a full line, and below the last line.
        clipsToBounds = false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private static func configure(_ view: UITextView) {
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = false
        view.backgroundColor = .clear
    }

    /// The text view whose text shows: the field, or the placeholder in its place.
    var shownTextView: UITextView {
        isEmptyDraft ? placeholderView : self
    }

    override var accessibilityValue: String? {
        get { text.isEmpty ? accessibilityPlaceholder : text }
        set { super.accessibilityValue = newValue }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        placeholderView.frame = CGRect(
            origin: .zero,
            size: placeholderView.fittingSize(width: bounds.width),
        )
        placeCursor()
    }

    /// The caret's color is clear while there is no range, so the `_` is the only cursor; a
    /// range shows the system highlight. The `_` blinks, lit again from every move
    /// (`restartsBlink`).
    func updateCursor(restartsBlink: Bool) {
        let isRange = isFirstResponder && selectedRange.length > 0
        tintColor = isRange ? nil : .clear
        placeCursor()
        let layer = cursorView.layer
        guard isEditingLook, blinks, !isRange else {
            layer.removeAnimation(forKey: Self.blinkKey)
            return
        }
        guard restartsBlink || layer.animation(forKey: Self.blinkKey) == nil else { return }
        // Discrete: lit for the first half of each cycle, dark for the second, no fade.
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [1, 0]
        blink.keyTimes = [0, 0.5, 1]
        blink.calculationMode = .discrete
        blink.duration = Self.blinkInterval * 2
        blink.repeatCount = .infinity
        layer.add(blink, forKey: Self.blinkKey)
    }

    /// Under the character typing will push along, or after the last one: where the text system
    /// draws its caret. Under the placeholder's first letter while editing an empty field, and
    /// after the text at rest. Hidden for a range.
    private func placeCursor() {
        let shown = shownTextView
        shown.ensureLayout()
        let position: UITextPosition
        if !isEditingLook {
            position = shown.endOfDocument
        } else if isEmptyDraft {
            position = beginningOfDocument
        } else if let range = selectedTextRange, range.isEmpty {
            position = range.start
        } else {
            cursorView.isHidden = true
            return
        }
        let caret = (isEditingLook ? self : shown).caretRect(for: position)
        guard caret.minX.isFinite, caret.minY.isFinite else {
            cursorView.isHidden = true
            return
        }
        cursorView.isHidden = false
        // The width follows the caret at once, never animated with whatever layout is moving.
        UIView.performWithoutAnimation {
            cursorView.transform = .identity
            cursorView.sizeToFit()
            // The `_` is one SF Mono cell, the width of every character the font has.
            let cell = cursorView.bounds.size
            let width = isEditingLook && !isEmptyDraft ? widthOfCharacter(at: position) : 0
            let scale = max(1, width / cell.width)
            cursorView.transform = CGAffineTransform(scaleX: scale, y: 1)
            cursorView.center = CGPoint(
                x: caret.minX + cell.width * scale / 2,
                y: caret.minY + drop + cell.height / 2,
            )
        }
    }

    /// How wide the character after `position` is drawn, the whole grapheme cluster, so the
    /// `_` under an emoji or a CJK character spans it; 0 at the end of the text.
    private func widthOfCharacter(at position: UITextPosition) -> CGFloat {
        let location = offset(from: beginningOfDocument, to: position)
        let string = text as NSString
        guard location < string.length else { return 0 }
        let characterRange = string.rangeOfComposedCharacterSequence(at: location)
        guard let start = self.position(from: beginningOfDocument, offset: characterRange.location),
              let end = self.position(from: start, offset: characterRange.length),
              let range = textRange(from: start, to: end)
        else { return 0 }
        let rect = firstRect(for: range)
        return rect.width.isFinite ? rect.width : 0
    }
}

extension UITextView {
    /// Lays out the whole text, so sizes and caret rects read from it are final. The title is
    /// short, so this is cheap.
    fileprivate func ensureLayout() {
        if let layout = textLayoutManager {
            layout.ensureLayout(for: layout.documentRange)
        }
    }

    /// The height its text takes at `width`.
    fileprivate func fittingSize(width: CGFloat) -> CGSize {
        ensureLayout()
        let size = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: min(width, size.width), height: size.height)
    }
}

extension Color {
    fileprivate func uiColor(in environment: EnvironmentValues) -> UIColor {
        UIColor(cgColor: resolve(in: environment).cgColor)
    }
}
#endif
