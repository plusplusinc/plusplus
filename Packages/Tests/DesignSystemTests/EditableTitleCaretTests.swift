// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import CoreText
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// Where the `_` is drawn for each place of the caret, read against where CoreText, laying the
/// same text out at the same width, puts the characters around it: under the character after
/// the caret, as wide as that character, or one cell after the last one; and on the
/// character's line, the drop below its top.
@MainActor
@Suite("Editable title's _ under the caret")
struct EditableTitleCaretTests {
    private nonisolated static let large = UIContentSizeCategory.large
    private nonisolated static let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge

    /// Names with characters wider than a cell of the title's font, at the routine screen's
    /// width: emoji, and Chinese, which SF Mono lacks.
    nonisolated static let wideNames = [
        "Legs 💪💪💪💪💪💪💪 and back",
        "上半身和下半身力量训练",
    ]

    /// The title editing `draft` at `width`, in a window at `category`.
    private final class Screen {
        let window: UIWindow
        let field: TitleFieldView

        init(_ draft: String, width: CGFloat, at category: UIContentSizeCategory) throws {
            let host = UIHostingController(rootView: EditableTitleContent(
                draft: .constant(draft),
                placeholder: "New routine",
                shownPlaceholder: "New routine",
                isEditing: true,
                blinks: false,
                accessibilityLabel: "Routine name",
                accessibilityHint: "Renames the routine.",
            )
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: width))
            host.safeAreaRegions = []
            window = .sceneless(hosting: host, at: category)
            window.layoutIfNeeded()
            func field(in view: UIView) -> TitleFieldView? {
                view as? TitleFieldView ?? view.subviews.lazy.compactMap(field(in:)).first
            }
            self.field = try #require(field(in: host.view))
        }

        isolated deinit {
            window.isHidden = true
        }

        /// The `_`'s frame, in the field, with the caret before UTF-16 offset `location`.
        func cursor(at location: Int) -> CGRect {
            field.selectedRange = NSRange(location: location, length: 0)
            field.setNeedsLayout()
            field.layoutIfNeeded()
            return field.cursorView.frame
        }

        /// The rect the text system gives the character at UTF-16 range `range`, in the field.
        func rect(of range: NSRange) -> CGRect {
            let start = field.position(from: field.beginningOfDocument, offset: range.location)
            let end = start.flatMap { field.position(from: $0, offset: range.length) }
            guard let start, let end, let textRange = field.textRange(from: start, to: end)
            else { return .null }
            return field.firstRect(for: textRange)
        }
    }

    /// The field's text laid out by CoreText at `width`: its lines.
    private struct Layout {
        let lines: [LaidOutLine]

        init(_ text: NSAttributedString, width: CGFloat) {
            let setter = CTFramesetterCreateWithAttributedString(text)
            let path = CGPath(
                rect: CGRect(x: 0, y: 0, width: width, height: 10000),
                transform: nil,
            )
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
            lines = (CTFrameGetLines(frame) as? [CTLine] ?? []).map {
                LaidOutLine(range: CTLineGetStringRange($0), line: $0)
            }
        }

        /// Where a caret before UTF-16 offset `index` is: on the line that starts there at a
        /// break, or the last line at the end.
        func place(at index: Int) -> CaretPlace {
            let number = lines.firstIndex { index < $0.range.location + $0.range.length }
                ?? lines.count - 1
            let line = lines[number]
            return CaretPlace(
                line: number,
                offset: CTLineGetOffsetForStringIndex(line.line, index, nil),
            )
        }
    }

    /// How far the `_` sits below the top of its line at `category`, as the title scales it.
    private static func drop(at category: UIContentSizeCategory) -> CGFloat {
        UIFontMetrics(forTextStyle: .title2).scaledValue(
            for: ScreenTitle.cursorDrop,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: category),
        )
    }

    /// One cell of the title's font at `category`.
    private static func cell(at category: UIContentSizeCategory) -> CGFloat {
        let size = UIFontMetrics(forTextStyle: .title2).scaledValue(
            for: ScreenTitle.size,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: category),
        )
        return ("_" as NSString)
            .size(withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: size, weight: .bold)])
            .width
    }

    /// Checks the `_` at every place of the caret in `draft`: under each character, spanning
    /// it, then one cell after the last. Returns the screen and CoreText's layout, for more checks.
    @discardableResult
    private func check(
        _ draft: String,
        width: CGFloat,
        at category: UIContentSizeCategory,
    ) throws -> (screen: Screen, layout: Layout) {
        let screen = try Screen(draft, width: width, at: category)
        let layout = Layout(screen.field.attributedText, width: width)
        let drop = Self.drop(at: category)
        let cell = Self.cell(at: category)
        let string = draft as NSString
        var location = 0
        while location <= string.length {
            let place = layout.place(at: location)
            let atEnd = location == string.length
            let range = atEnd
                ? NSRange(location: location, length: 0)
                : string.rangeOfComposedCharacterSequence(at: location)
            let next = layout.place(at: NSMaxRange(range))
            let cursor = screen.cursor(at: location)
            let name = atEnd ? "the end" : "before \(string.substring(with: range))"
            let label = "\(name) at \(location), \(category.rawValue)"
            #expect(abs(cursor.minX - place.offset) <= 0.5, "\(label): x")
            // The character's rect reaches a point above its line, and CoreText's lines can be
            // a different height from the text system's where a fallback font joins the line.
            let character = screen.rect(of: atEnd
                ? string.rangeOfComposedCharacterSequence(at: location - 1)
                : range)
            let lineTop = cursor.minY - drop
            #expect(
                lineTop >= character.minY - 0.01 && lineTop <= character.minY + 1.5,
                "\(label): y \(lineTop) on a line from \(character.minY)",
            )
            // At a line's end the next place is on the next line, so a width reads from it only
            // within a line.
            if atEnd || next.line == place.line {
                let expected = max(cell, atEnd ? 0 : next.offset - place.offset)
                #expect(abs(cursor.width - expected) <= 0.5, "\(label): width")
            }
            location = atEnd ? location + 1 : NSMaxRange(range)
        }
        return (screen, layout)
    }

    @Test(
        "The _ is under the character after the caret, as wide as it, at every place",
        arguments: wideNames,
        [large, ax5],
    )
    func wideName(draft: String, category: UIContentSizeCategory) throws {
        try check(draft, width: 370, at: category)
    }

    @Test(
        "Wrapped at the /, the _ is under each character on both lines, a whole cell each",
        arguments: [large, ax5],
    )
    func wrapAtSlash(category: UIContentSizeCategory) throws {
        let draft = "Push/pull day"
        // Room for "Push/" and "pull day", and not "Push/pull".
        let cell = Self.cell(at: category)
        let (screen, layout) = try check(draft, width: cell * 8.5, at: category)
        try #require(layout.lines.count == 2, "the name does not wrap")
        try #require(layout.lines[1].range.location == 5, "the name does not wrap at the /")
        // In SF Mono every character is a cell, so the `_` is a whole number of cells along
        // its line, as main drew it: "Push/" on line 1, "pull day" on line 2.
        for location in 0 ... 13 {
            let column = location < 5 ? location : location - 5
            let cursor = screen.cursor(at: location)
            #expect(abs(cursor.minX - CGFloat(column) * cell) <= 0.5, "column at \(location)")
        }
    }
}

/// A line CoreText laid out: its characters, and the line.
private struct LaidOutLine {
    let range: CFRange
    let line: CTLine
}

/// A place of the caret CoreText laid out: its line's number, and how far along it is.
private struct CaretPlace {
    let line: Int
    let offset: CGFloat
}

#endif
