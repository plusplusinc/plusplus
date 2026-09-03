// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
@testable import DesignSystem

/// Visual regression coverage for the token palette.
///
/// A wrong light/dark pair is invisible in code review and obvious in an image. The list of
/// tokens is read from the asset catalog on disk, so a token added there cannot be missing here.
@Suite("Design tokens")
struct TokenSnapshotTests {
    private static let catalog = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/DesignSystem/Resources/Tokens.xcassets")

    private static func tokenNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(at: catalog, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "colorset" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    private func palette(_ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(names, id: \.self) { name in
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(Color.token(name))
                        .frame(width: 44, height: 28)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm)
                                .strokeBorder(Color.ppSeparator),
                        )
                    Text(name)
                        .font(.ppCaption)
                        .foregroundStyle(Color.ppTextPrimary)
                }
            }
        }
        .padding(Spacing.md)
        .background(Color.ppBackground)
    }

    @Test("Every token in the catalog renders in light, dark, and XXXL")
    func palette() throws {
        let names = try Self.tokenNames()
        try #require(!names.isEmpty, "no colorsets found at \(Self.catalog.path())")
        assertThemedSnapshots(of: palette(names), width: 260)
    }
}

#endif
