// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SnapshotTesting
import SwiftUI
import Testing

/// Snapshots a view in the three appearances every component must survive: light, dark, and
/// the largest accessibility content size. The scheme pins the test language so the system
/// font's line height, which follows the device's preferred languages, is the same everywhere.
///
/// The width is explicit because `.sizeThatFits` proposes zero width and `Text` truncates to
/// nothing, producing a silently wrong reference image. Comparison is perceptual so text
/// rasterization differences between machines do not read as design regressions.
///
/// References live in `__Snapshots__/<TestFile>` at the test target's root, which is where
/// recording writes, including a new suite's first recording. When `__Snapshots__` itself is
/// absent, as on Xcode Cloud's test machines, which have the built products but not the source
/// checkout, the copy bundled into the test target is used.
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
    let directory = snapshotDirectory(
        forSuite: URL(filePath: "\(file)").deletingPathExtension().lastPathComponent,
    )
    for appearance in appearances {
        let failure = verifySnapshot(
            of: view.frame(width: width).fixedSize(horizontal: false, vertical: true),
            as: .image(
                precision: 0.99,
                perceptualPrecision: 0.98,
                layout: .fixed(width: width, height: 0),
                traits: appearance.traits,
            ),
            named: appearance.name,
            snapshotDirectory: directory,
            fileID: fileID,
            file: file,
            testName: testName,
            line: line,
            column: column,
        )
        if let failure {
            Issue.record(
                Comment(rawValue: failure),
                sourceLocation: SourceLocation(
                    fileID: "\(fileID)", filePath: "\(file)", line: Int(line), column: Int(column),
                ),
            )
        }
    }
}

/// The test target's root in the source tree: this file's folder, which `Package.swift` copies
/// `__Snapshots__` from.
private let targetRoot = URL(filePath: #filePath).deletingLastPathComponent()

/// Where a suite's references are read and recorded. Decided by the shared `__Snapshots__`
/// folder, not the suite's own: a new suite has no folder yet, and its first recording belongs
/// in the source tree, not in the built bundle.
func snapshotDirectory(forSuite name: String, sourceRoot: URL = targetRoot) -> String {
    let inSourceTree = sourceRoot.appending(path: "__Snapshots__")
    let root = FileManager.default.fileExists(atPath: inSourceTree.path(percentEncoded: false))
        ? inSourceTree
        : Bundle.module.url(forResource: "__Snapshots__", withExtension: nil)
    guard let root else {
        fatalError("__Snapshots__ is neither in \(sourceRoot.path()) nor bundled with the tests")
    }
    return root.appending(path: name).path(percentEncoded: false)
}

#endif
