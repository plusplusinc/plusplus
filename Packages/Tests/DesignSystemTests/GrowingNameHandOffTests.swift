// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// Where a growing name's drawn letters end, across, as it hands off between a row's size and
/// the growing one: the grown name scaled down at the first moment of growth against the row's
/// name at rest, both laid out and measured by the view itself. The package's logic tests give
/// the scale its widths by hand; this one sees the widths the view measures reach the drawing.
@MainActor
@Suite("Growing name's hand-off")
struct GrowingNameHandOffTests {
    /// A row's label width: the screen's 402 less the list's insets and the rail's room.
    private static let width: CGFloat = 326

    /// How far across `title` is drawn at `growth`, in points, from its first covered column to its
    /// last.
    private func inkWidth(_ title: String, growth: CGFloat, at category: UIContentSizeCategory)
        throws -> CGFloat
    {
        let coverage = try Coverage(
            of: GrowingName(title: title, growth: growth)
                .frame(width: Self.width, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true),
            at: category,
        )
        // Only how far the letters reach across from their own leading edge counts.
        let columns = coverage.coveredColumns()
        let first = try #require(columns.first, "Nothing drawn for \(title)")
        let last = try #require(columns.last)
        return CGFloat(last + 1 - first) / CGFloat(Coverage.scale)
    }

    /// Names that break alike in both sizes at the text size, and one that breaks apart, which
    /// crossfades.
    nonisolated static let cases: [(String, UIContentSizeCategory)] = [
        ("Barbell back squat", .large),
        ("Plank", .accessibilityExtraExtraExtraLarge),
        ("Kneeling hip flexor stretch", .large),
    ]

    @Test(
        "Just off rest, the name ends across within a point of where the row's name at rest does",
        arguments: cases,
    )
    func handOffKeepsWidth(title: String, category: UIContentSizeCategory) throws {
        let resting = try inkWidth(title, growth: 0, at: category)
        let leaving = try inkWidth(title, growth: 0.001, at: category)
        // Within a point: the letters' own nudge at the hand-off is under one. Before the scale
        // across took the measured width, "Barbell back squat" stepped about 4.7 points.
        #expect(abs(leaving - resting) < 1, "\(title): \(resting) at rest, \(leaving) leaving it")
    }
}

#endif
