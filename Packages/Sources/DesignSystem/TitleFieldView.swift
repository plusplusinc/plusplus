#if os(iOS)
import UIKit

/// The field, with the placeholder under its text and the `_` over it.
final class TitleFieldView: UITextView, UIEditMenuInteractionDelegate {
    /// Laid out as the field is, so moving between the two keeps the height when the strings
    /// match.
    let placeholderView = UITextView()
    let cursorView = CursorMark()
    var drop: CGFloat = 0
    /// Where a touch counts as on the title, in the window: the field, and at least
    /// `ScreenTitle.touchTarget` tall, as `EditableTitle`'s target behind a short title is.
    var touchTargetInWindow: CGRect {
        convert(
            CGRect(
                x: 0,
                y: 0,
                width: bounds.width,
                height: max(bounds.height, ScreenTitle.touchTarget),
            ),
            to: nil,
        )
    }

    /// Whether the placeholder shows in the field's place.
    var isEmptyDraft: Bool {
        text.isEmpty
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

        // Placed and stretched from its top leading corner, which lands where the text's
        // characters do: a center can fall between pixels and draw the `_` a pixel off.
        cursorView.layer.anchorPoint = .zero
        cursorView.isUserInteractionEnabled = false
        cursorView.isAccessibilityElement = false
        cursorView.accessibilityElementsHidden = true
        addSubview(cursorView)
        // The `_` hangs past the trailing edge after a full line, and below the last line.
        clipsToBounds = false
        addGestureRecognizer(focusTap)
        addGestureRecognizer(focusPress)
        addInteraction(editMenu)
    }

    /// The tap that starts an edit. UIKit's own tap would place the caret where it lands, after
    /// editing has begun and put it at the end, where an edit starts.
    private lazy var focusTap = UITapGestureRecognizer(target: self, action: #selector(focus))

    /// The long press that starts an edit, the caret at the end as for a tap, and shows the edit
    /// menu, as a text field does. UIKit's own long press on a text view only moves the caret.
    private lazy var focusPress = UILongPressGestureRecognizer(
        target: self,
        action: #selector(focusWithMenu),
    )

    /// The edit menu a long press shows. Its items are the field's own: what it can do with its
    /// text and the clipboard.
    private lazy var editMenu = UIEditMenuInteraction(delegate: self)

    @objc private func focus() {
        _ = becomeFirstResponder()
    }

    @objc private func focusWithMenu(_ press: UILongPressGestureRecognizer) {
        guard press.state == .began else { return }
        focus()
        guard isFirstResponder, let caret = selectedTextRange?.end else { return }
        let rect = caretRect(for: caret)
        editMenu.presentEditMenu(with: UIEditMenuConfiguration(
            identifier: nil,
            sourcePoint: CGPoint(x: rect.midX, y: rect.midY),
        ))
    }

    /// The menu sits clear of the caret's line, as a text field's does.
    func editMenuInteraction(
        _: UIEditMenuInteraction,
        targetRectFor _: UIEditMenuConfiguration,
    ) -> CGRect {
        selectedTextRange.map { caretRect(for: $0.end) } ?? .null
    }

    /// Until the field has focus it takes a touch as a whole, so only `focusTap` and
    /// `focusPress` see it, and not the text interaction on its subviews, which would put the
    /// caret under the finger.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit != nil && !isFirstResponder ? self : hit
    }

    /// Until the field has focus, only `focusTap` and `focusPress` act on it; once it has, only
    /// UIKit's own text gestures do, to move the caret or select. Disabled, the two take no part
    /// in them.
    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        recognizer === focusTap || recognizer === focusPress || isFirstResponder && super
            .gestureRecognizerShouldBegin(recognizer)
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        focusTap.isEnabled = !isFirstResponder
        focusPress.isEnabled = !isFirstResponder
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        focusTap.isEnabled = !isFirstResponder
        focusPress.isEnabled = !isFirstResponder
        return resigned
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private static func configure(_ view: UITextView) {
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = false
        // Never scrolled, so no indicators, which VoiceOver would list as empty sliders.
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
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
        placeholderView.isHidden = !isEmptyDraft
        placeholderView.frame = CGRect(
            origin: .zero,
            size: placeholderView.fittingSize(
                width: bounds.width,
                scale: traitCollection.displayScale,
            ),
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

    /// Under the character typing will push along, as wide as it is drawn, or one cell after
    /// the last one. Under the placeholder's first letter while editing an empty field, and after
    /// the text at rest. Hidden for a range.
    private func placeCursor() {
        let shown = shownTextView
        shown.ensureLayout()
        let location: Int
        if !isEditingLook {
            location = shown.textStorage.length
        } else if isEmptyDraft {
            location = 0
        } else if selectedRange.length == 0 {
            location = selectedRange.location
        } else {
            cursorView.isHidden = true
            return
        }
        guard let place = shown.cursorPlace(at: location) else {
            cursorView.isHidden = true
            return
        }
        cursorView.isHidden = false
        // The width follows the caret at once, never animated with whatever layout is moving.
        UIView.performWithoutAnimation {
            cursorView.transform = .identity
            // The `_` is one SF Mono cell, the width of every character the font has.
            cursorView.sizeToFit()
            let width = isEditingLook && !isEmptyDraft ? place.width : 0
            let scale = max(1, width / cursorView.bounds.width)
            cursorView.transform = CGAffineTransform(scaleX: scale, y: 1)
            cursorView.layer.position = CGPoint(x: place.minX, y: place.minY + drop)
        }
    }
}

/// The `_`, drawn as the text is, at a fractional place when that is where the character is:
/// a label rounds its size and its text's place to whole pixels, a third of a point off.
final class CursorMark: UIView {
    var font = ScreenTitle.uiFont(ofSize: ScreenTitle.size) {
        didSet {
            if font != oldValue {
                setNeedsDisplay()
            }
        }
    }

    var textColor = UIColor.label {
        didSet {
            if textColor != oldValue {
                setNeedsDisplay()
            }
        }
    }

    private var mark: NSAttributedString {
        NSAttributedString(string: "_", attributes: [.font: font, .foregroundColor: textColor])
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// One cell of the font, the `_`'s own size, rounded up to whole pixels, so the `_` is drawn
    /// at its size rather than stretched to fit a bitmap a fraction of a pixel wider.
    override func sizeThatFits(_: CGSize) -> CGSize {
        let scale = max(traitCollection.displayScale, 1)
        let cell = mark.size()
        return CGSize(
            width: (cell.width * scale).rounded(.up) / scale,
            height: (cell.height * scale).rounded(.up) / scale,
        )
    }

    override func draw(_: CGRect) {
        mark.draw(at: .zero)
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

    /// Where the `_` goes for a caret before UTF-16 offset `location`: the top of its line, at
    /// the leading edge of the character there, as wide as that character is drawn, the whole
    /// grapheme cluster, so the `_` under an emoji or a CJK character spans it; at the end,
    /// after the last character, zero wide. A caret at a line break is on the line after it, as
    /// the text system draws it. Read from the text's own lines rather than `caretRect(for:)`
    /// or `firstRect(for:)`, which reach a point above the line and round to whole points.
    fileprivate func cursorPlace(at location: Int) -> CGRect? {
        guard let layout = textLayoutManager, let content = layout.textContentManager else {
            return nil
        }
        let string = textStorage.string as NSString
        let documentStart = layout.documentRange.location
        var place: CGRect?
        layout.enumerateTextLayoutFragments(from: documentStart) { fragment in
            let start = content.offset(from: documentStart, to: fragment.rangeInElement.location)
            let frame = fragment.layoutFragmentFrame
            for line in fragment.textLineFragments {
                let range = line.characterRange
                let index = location - start
                let isLast = line === fragment.textLineFragments.last
                guard index < NSMaxRange(range) || isLast && index == NSMaxRange(range) else {
                    continue
                }
                let end = index < string.length - start
                    ? string.rangeOfComposedCharacterSequence(at: location).upperBound - start
                    : index
                let leading = line.locationForCharacter(at: index).x
                place = CGRect(
                    x: frame.minX + line.typographicBounds.minX + leading,
                    y: frame.minY + line.typographicBounds.minY,
                    width: line.locationForCharacter(at: min(end, NSMaxRange(range))).x - leading,
                    height: line.typographicBounds.height,
                )
                return false
            }
            return true
        }
        return place ?? (string.length == 0 ? .zero : nil)
    }

    /// The size its text takes at `width`, its height on the pixel grid at `scale`, where the
    /// text view rounds it up to. Re-expressed as a whole number of pixels times the size of
    /// one: divided by 3 instead, a third lands a hair over its true value, and a stack of such
    /// heights can then round up to the next pixel.
    func fittingSize(width: CGFloat, scale: CGFloat) -> CGSize {
        ensureLayout()
        let size = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let pixel = 1 / max(scale, 1)
        return CGSize(
            width: min(width, size.width),
            height: (size.height / pixel).rounded() * pixel,
        )
    }
}
#endif
