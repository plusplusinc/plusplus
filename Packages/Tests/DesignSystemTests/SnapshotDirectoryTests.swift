// Runs only where UIKit exists, alongside the snapshot helper it tests.
#if canImport(UIKit) && !os(watchOS)

import Foundation
import Testing

/// Where `assertThemedSnapshots` reads and records references, so a new suite's first recording
/// lands where it can be committed.
@Suite("Snapshot directory")
struct SnapshotDirectoryTests {
    @Test("A suite with no folder yet records into the source tree")
    func newSuiteRecordsIntoSourceTree() throws {
        let source = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(
            at: source.appending(path: "__Snapshots__"), withIntermediateDirectories: true,
        )
        defer { try? FileManager.default.removeItem(at: source) }

        let expected = source.appending(path: "__Snapshots__/NewSuiteTests")
        #expect(
            snapshotDirectory(forSuite: "NewSuiteTests", sourceRoot: source)
                == expected.path(percentEncoded: false),
        )
    }

    @Test("Without a source tree, the bundled references are used")
    func noSourceTreeUsesBundle() {
        let missing = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

        let directory = snapshotDirectory(forSuite: "TokenSnapshotTests", sourceRoot: missing)

        #expect(directory.hasPrefix(Bundle.module.bundlePath))
        #expect(FileManager.default.fileExists(atPath: "\(directory)/palette.light.png"))
    }
}

#endif
