import Foundation
import Testing
import PlusPlusKit

/// Docs-as-tests: the JSON examples in docs/PLATFORM.md are part of the
/// interchange contract, so they must actually decode and validate. This
/// is the anti-staleness mechanism for the format docs — change the
/// schema without updating PLATFORM.md and this test fails on Linux CI.
@Suite("PLATFORM.md examples")
struct DocsConformanceTests {
    /// Repo root found by walking up from this file's compile-time path —
    /// robust to #filePath being absolute (xcodebuild) or relative to
    /// either the package dir or the repo root (SwiftPM on Linux).
    private var platformDocURL: URL? {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent("docs/PLATFORM.md")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    private func fencedJSONBlocks(in text: String) -> [String] {
        var blocks: [String] = []
        var current: [Substring] = []
        var inJSON = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if inJSON {
                if line.hasPrefix("```") {
                    blocks.append(current.joined(separator: "\n"))
                    current = []
                    inJSON = false
                } else {
                    current.append(line)
                }
            } else if line.trimmingCharacters(in: .whitespaces) == "```json" {
                inJSON = true
            }
        }
        return blocks
    }

    @Test("Every complete bundle example decodes and validates clean")
    func bundleExamplesAreLive() throws {
        let url = try #require(platformDocURL, "docs/PLATFORM.md not found above \(#filePath)")
        let text = try String(contentsOf: url, encoding: .utf8)
        let bundles = fencedJSONBlocks(in: text)
            // Prose fragments use ellipses; only whole-bundle examples
            // (they declare the exercises key) are decodable contracts.
            .filter { !$0.contains("…") && $0.contains("\"exercises\"") }

        try #require(!bundles.isEmpty, "PLATFORM.md lost its bundle example — update this test's expectations deliberately, not by accident")

        for (index, block) in bundles.enumerated() {
            let bundle = try InterchangeCodec.decode(ExportBundle.self, from: Data(block.utf8))
            let issues = InterchangeValidator.validate(bundle)
            #expect(issues.isEmpty, "PLATFORM.md bundle example \(index) fails validation: \(issues)")
        }
    }

    @Test("Documented field names exist on the DTOs they describe")
    func documentedFieldsExist() throws {
        let url = try #require(platformDocURL, "docs/PLATFORM.md not found above \(#filePath)")
        let text = try String(contentsOf: url, encoding: .utf8)

        // Spot-check contract vocabulary the doc leans on. Encoding a
        // fully-populated DTO and checking its keys ties the doc's words
        // to the real schema without hand-maintaining a field list.
        let exercise = ExerciseDTO(
            name: "Probe", muscleGroup: .chest, exerciseType: .weightReps,
            equipment: [], notes: "n", videoURL: "https://example.com",
            defaultWeight: 1, defaultReps: 2, defaultRepsUpper: 3,
            defaultDurationSeconds: 4
        )
        let encoded = String(decoding: try InterchangeCodec.encode(
            ExportBundle(exercises: [exercise], routines: [], sessions: [])
        ), as: UTF8.self)

        for field in ["defaultWeight", "defaultReps", "defaultRepsUpper", "defaultDurationSeconds"] {
            #expect(encoded.contains("\"\(field)\""), "\(field) missing from encoded DTO")
            #expect(text.contains(field), "PLATFORM.md never mentions \(field) but the schema carries it")
        }
    }
}
