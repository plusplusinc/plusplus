// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SnapshotTesting
import SwiftUI
import Testing

/// Snapshots a view in the three appearances every component must survive: light, dark, and
/// the largest accessibility content size.
///
/// The width is explicit because `.sizeThatFits` proposes zero width and `Text` truncates to
/// nothing, producing a silently wrong reference image. Comparison is perceptual so text
/// rasterization differences between machines do not read as design regressions.
@MainActor
func assertThemedSnapshots(
    of view: some View,
    width: CGFloat,
    fileID: StaticString = #fileID,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column,
) {
    let appearances: [(name: String, traits: UITraitCollection)] = [
        ("light", UITraitCollection { $0.userInterfaceStyle = .light }),
        ("dark", UITraitCollection { $0.userInterfaceStyle = .dark }),
        (
            "xxxl",
            UITraitCollection {
                $0.userInterfaceStyle = .light
                $0.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            },
        ),
    ]
    for appearance in appearances {
        assertSnapshot(
            of: view.frame(width: width).fixedSize(horizontal: false, vertical: true),
            as: .image(
                precision: 0.99,
                perceptualPrecision: 0.98,
                layout: .fixed(width: width, height: 0),
                traits: appearance.traits,
            ),
            named: appearance.name,
            fileID: fileID,
            file: file,
            testName: testName,
            line: line,
            column: column,
        )
    }
}

#endif
