// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// Where a row's node sits against its name's first line, read from the pixels drawn: the node's
/// center as a share of the way down the letters, from their top to the baseline. A name grown
/// larger than a row's raises the node with its letters, so the share stays a resting row's. On
/// the baseline alone, the node kept a row's height above it and sat low on the large name.
@MainActor
@Suite("Rail node on its name")
struct RailNodeCenterTests {
    private nonisolated static let large = UIContentSizeCategory.large
    private nonisolated static let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge

    /// One word, so it breaks alike at both sizes and the large name draws throughout, and no
    /// descender, so the letters' lowest ink is the baseline.
    private static let title = "Deadlift"

    /// Where the node's center is down the name's first line, in pixels, and that as a share of
    /// the letters' height.
    private struct Place {
        var nodeCenter: CGFloat
        var share: CGFloat
    }

    private func place(of row: some View, at category: UIContentSizeCategory) throws -> Place {
        let coverage = try Coverage(
            of: row
                .frame(width: 370, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true),
            at: category,
        )
        // The node is the first run of drawn columns from the leading edge, and the name is
        // what is drawn after it.
        let columns = Coverage.runs(coverage.coveredColumns())
        let node = try #require(columns.first, "Nothing drawn")
        let name = try #require(columns.dropFirst().first, "No name beside the node")
        let nodeRows = try #require(
            Coverage.runs(coverage.coveredRows(in: node.lowerBound ..< node.upperBound + 1)).first,
        )
        // The name's first line, from its letters' top to the baseline, with no descender.
        let line = try #require(
            Coverage.runs(coverage.coveredRows(in: name.lowerBound ..< coverage.width)).first,
        )
        let (nodeTop, nodeBottom, inkTop, baseline) =
            (nodeRows.lowerBound, nodeRows.upperBound, line.lowerBound, line.upperBound + 1)
        let nodeCenter = CGFloat(nodeTop + nodeBottom + 1) / 2
        return Place(
            nodeCenter: nodeCenter,
            share: (nodeCenter - CGFloat(inkTop)) / CGFloat(baseline - inkTop),
        )
    }

    private func growing(_ growth: CGFloat) -> some View {
        GrowingName(title: Self.title, growth: growth).railRow()
    }

    /// Within this share of the letters' height: a pixel either way at the node's two edges and
    /// the letters'. On the baseline alone, the grown name's share was about 0.2 under a row's.
    private static let tolerance: CGFloat = 0.05

    @Test(
        "As a name grows from a row's size, its node keeps a row's place against its letters",
        arguments: [large, ax5],
    )
    func keepsPlaceThroughGrowth(category: UIContentSizeCategory) throws {
        let resting = try place(of: growing(0), at: category)
        // Just off both ends too: a node placed one way at rest and another once growing steps.
        for growth: CGFloat in [0.001, 0.5, 0.999, 1] {
            let grown = try place(of: growing(growth), at: category)
            #expect(
                abs(grown.share - resting.share) < Self.tolerance,
                "\(category.rawValue), growth \(growth): \(grown.share), \(resting.share) at rest",
            )
        }
    }

    @Test(
        "The current exercise's node sits on its large name where a row's sits on its name",
        arguments: [large, ax5],
    )
    func currentLabel(category: UIContentSizeCategory) throws {
        let focus = RowFocus(
            progress: "Set 1 of 3",
            equipment: ["Barbell"],
            figures: [.init(number: "5", unit: "reps"), .init(number: "225", unit: "lb")],
            spokenFigures: "5 reps, 225 pounds",
        )
        let detail = ["3 × 5 reps", "225 lb"]
        let resting = try place(
            of: RowLabel(title: Self.title, detail: detail).railRow(),
            at: category,
        )
        let current = try place(
            of: RowLabel(title: Self.title, detail: detail, focus: focus).railRow(),
            at: category,
        )
        #expect(
            abs(current.share - resting.share) < Self.tolerance,
            "\(category.rawValue): \(current.share) down the letters, \(resting.share) on a row",
        )
    }

    @Test("At rest, the node sits on a name exactly as on plain text", arguments: [large, ax5])
    func restingUnchanged(category: UIContentSizeCategory) throws {
        let name = try place(of: growing(0), at: category)
        let text = try place(
            of: Text(Self.title).font(.ppRowTitle).railRow(),
            at: category,
        )
        #expect(name.nodeCenter == text.nodeCenter, "\(category.rawValue)")
    }
}

#endif
