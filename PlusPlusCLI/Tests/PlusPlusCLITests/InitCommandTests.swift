import Foundation
import Testing
import PlusPlusKit
@testable import plusplus

@Suite("plusplus init")
struct InitCommandTests {
    private func makeTempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("plusplus-init-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Scaffold plan covers README, gitattributes, and the three directories")
    func scaffoldPlan() throws {
        let paths = try InitCommand.scaffoldFiles(example: false).map(\.path)
        #expect(paths.contains("README.md"))
        #expect(paths.contains(".gitattributes"))
        #expect(paths.contains("program/exercises/.gitkeep"))
        #expect(paths.contains("program/routines/.gitkeep"))
        #expect(paths.contains("history/.gitkeep"))
    }

    @Test("Example scaffold lints clean")
    func exampleLintsClean() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        for file in try InitCommand.scaffoldFiles(example: true) {
            let target = root.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try file.data.write(to: target)
        }

        let bundle = try BundleSource.load(path: root.path)
        #expect(InterchangeValidator.validate(bundle).isEmpty)
        #expect(bundle.exercises.map(\.name) == ["Push-Up"])
        #expect(bundle.routines.map(\.name) == ["Example Day"])
    }

    @Test("Dotfiles don't block scaffolding; visible files do")
    func emptinessCheck() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(try InitCommand.isEffectivelyEmpty(root))

        // A fresh git clone (.git only) is still "empty".
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git"), withIntermediateDirectories: true
        )
        #expect(try InitCommand.isEffectivelyEmpty(root))

        try Data("x".utf8).write(to: root.appendingPathComponent("notes.txt"))
        #expect(try !InitCommand.isEffectivelyEmpty(root))
    }
}
