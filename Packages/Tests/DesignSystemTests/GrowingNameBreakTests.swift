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

    /// A name that fits one line, one that wraps, one of three lines, and a word wider than the
    /// row, each at a size where it does.
    nonisolated static let cases: [Case] = [
        Case(title: "Barbell back squat", category: .large, lines: 1),
        Case(title: "Dumbbell single-arm overhead triceps extension", category: .large, lines: 2),
        Case(
            title: "Neutral-grip weighted pull-up with a pause at the top",
            category: .extraLarge,
            lines: 3,
        ),
        Case(
            title: "Supercalifragilisticexpialidocious squat",
            category: .accessibilityExtraExtraExtraLarge,
            lines: 3,
        ),
    ]

    @Test(
        "A name breaks into the same lines at a row's size as at the current exercise's",
        arguments: cases,
    )
    func sameLinesAtBothSizes(_ name: Case) throws {
        let measured = try layOut(name.title, in: .ppCurrentTitle, at: name.category)
        let breaks = GrowingName.LineBreaks(title: name.title, layout: measured.layout)
        let broken = breaks.lines(of: name.title)
        let small = try layOut(broken, in: .ppRowTitle, at: name.category).lines
        let large = try layOut(broken, in: .ppCurrentTitle, at: name.category).lines
        #expect(measured.lines.count == name.lines, "Laid out as \(measured.lines)")
        #expect(large == measured.lines)
        #expect(small == large, "\(small) small, \(large) large")
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
        // The indices count from where the text starts in its storage, as `LineBreaks` reads them.
        let origin = layout.flatMap { $0.flatMap(\.characterIndices) }.min() ?? 0
        let lines = layout.map { line -> String in
            let indices = line.flatMap(\.characterIndices).map { $0 - origin }
            guard let first = indices.min(), let last = indices.max(), last < utf16.count
            else { return "" }
            return String(decoding: utf16[first ... last], as: UTF16.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (lines, layout)
    }

    private final class LayoutBox {
        var layout: Text.Layout?
    }
}

#endif
