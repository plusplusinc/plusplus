// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// A name's lines at both sizes, as the system lays them out at a row's width: the breaks read
/// from the large name (`GrowingName.LineBreaks`), then the name drawn with them at a row's size
/// and at the current exercise's. The package's logic tests give the breaks by hand; this one
/// sees the system's own layout of both.
@MainActor
@Suite("Growing name's line breaks")
struct GrowingNameBreakTests {
    /// A row's label width: the screen's 402 less the list's insets and the rail's room.
    private static let width: CGFloat = 326

    /// A name, the text size it is laid out at, and how many lines it breaks into there.
    struct Case: Sendable, CustomTestStringConvertible {
        let title: String
        let category: UIContentSizeCategory
        let lines: Int

        var testDescription: String {
            "\(title) at \(category.rawValue)"
        }
    }

    /// A name that fits one line, one that wraps at the default size, one of three lines at
    /// extra-large, and a word wider than the row, each laid out as the system breaks it there.
    nonisolated static let cases: [Case] = [
        Case(title: "Barbell back squat", category: .large, lines: 1),
        Case(title: "Dumbbell single-arm overhead triceps extension", category: .large, lines: 3),
        Case(
            title: "Neutral-grip weighted pull-up with a pause at the top",
            category: .extraLarge,
            lines: 3,
        ),
        Case(
            title: "Supercalifragilisticexpialidocious squat",
            category: .accessibilityExtraExtraExtraLarge,
            lines: 4,
        ),
    ]

    @Test(
        "A name breaks into the same lines at a row's size as at the current exercise's",
        arguments: cases,
    )
    func sameLinesAtBothSizes(_ name: Case) throws {
        let measured = try layOut(name.title, in: .ppCurrentTitle, at: name.category)
        #expect(measured.lines.count == name.lines, "Laid out as \(measured.lines)")
        // Drawn with a break at each line's start, the name holds the lines the large one has.
        let broken = GrowingName.LineBreaks(title: name.title, layout: measured.layout)
            .lines(of: name.title)
        #expect(broken.components(separatedBy: "\n") == measured.lines)
        // And neither size breaks any of them again.
        let small = try layOut(broken, in: .ppRowTitle, at: name.category).layout
        let large = try layOut(broken, in: .ppCurrentTitle, at: name.category).layout
        #expect(small.count == name.lines, "\(small.count) lines at a row's size")
        #expect(large.count == name.lines, "\(large.count) lines at the current exercise's")
    }

    /// Each line of `text` in `font`, as laid out a row's width wide at `category`, and the
    /// layout.
    private func layOut(_ text: String, in font: Font, at category: UIContentSizeCategory)
        throws -> (lines: [String], layout: Text.Layout)
    {
        let box = LayoutBox()
        let host = UIHostingController(rootView: Text(text)
            .font(font)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: Self.width, alignment: .topLeading)
            .onPreferenceChange(Text.LayoutKey.self) { box.layout = $0.first?.layout })
        let window = UIWindow.sceneless(hosting: host, at: category)
        defer { window.isHidden = true }
        window.settle()
        let layout = try #require(box.layout, "No layout for \(text)")
        let utf16 = Array(text.utf16)
        // Each line from its first character to the next line's, as `LineBreaks` reads them.
        let starts = GrowingName.LineBreaks(title: text, layout: layout).starts
        let bounds = [0] + starts + [utf16.count]
        let lines = zip(bounds, bounds.dropFirst()).map { from, upTo in
            String(decoding: utf16[from ..< upTo], as: UTF16.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (lines, layout)
    }

    private final class LayoutBox {
        var layout: Text.Layout?
    }
}

#endif
