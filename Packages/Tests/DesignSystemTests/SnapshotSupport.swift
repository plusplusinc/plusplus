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
///
/// References live in `__Snapshots__` next to the test file, which is where recording writes.
/// When that directory is absent, as on Xcode Cloud's test machines, which have the built
/// products but not the source checkout, the copy bundled into the test target is used.
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
    let directory = snapshotDirectory(forTestFile: file)
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

private func snapshotDirectory(forTestFile file: StaticString) -> String {
    let testFile = URL(filePath: "\(file)")
    let name = testFile.deletingPathExtension().lastPathComponent
    let inSourceTree = testFile.deletingLastPathComponent().appending(path: "__Snapshots__/\(name)")
    if FileManager.default.fileExists(atPath: inSourceTree.path()) {
        return inSourceTree.path()
    }
    guard let bundled = Bundle.module.url(forResource: "__Snapshots__", withExtension: nil) else {
        fatalError("__Snapshots__ is neither next to \(file) nor bundled in the test target")
    }
    return bundled.appending(path: name).path()
}

#endif
