// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast. The
// iOS simulator run is what actually exercises it.
#if canImport(UIKit) && !os(watchOS)

import SnapshotTesting
import SwiftUI
import Testing
@testable import DesignSystem

/// Visual regression coverage for the token palette itself.
///
/// There are no components yet, but the tokens are the part everything else will be built on,
/// and a wrong light/dark pair is invisible in code review and obvious in an image.
@Suite("Design tokens")
@MainActor
struct TokenSnapshotTests {
    private static let swatches: [(String, Color)] = [
        ("background", .ppBackground),
        ("surface", .ppSurface),
        ("surfaceElevated", .ppSurfaceElevated),
        ("textPrimary", .ppTextPrimary),
        ("textSecondary", .ppTextSecondary),
        ("accent", .ppAccent),
        ("positive", .ppPositive),
        ("warning", .ppWarning),
        ("danger", .ppDanger),
        ("separator", .ppSeparator),
    ]

    private var palette: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(Self.swatches, id: \.0) { name, color in
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(color)
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

    /// Proposed width matters: `.sizeThatFits` measures against a zero-width proposal, and
    /// `Text` truncates to nothing rather than claiming its ideal width. A fixed width with
    /// an intrinsic height is what keeps labels in the image.
    private static let width: CGFloat = 260

    @Test("Palette renders in light and dark")
    func palette_lightAndDark() {
        for (suffix, style) in [("light", UIUserInterfaceStyle.light), ("dark", .dark)] {
            assertSnapshot(
                of:
                palette
                    .frame(width: Self.width)
                    .fixedSize(horizontal: false, vertical: true),
                // Compared perceptually rather than pixel-exactly. Text rasterization differs
                // subtly between machines, so a strict match would fail on CI for reasons
                // that have nothing to do with the design.
                as: .image(
                    precision: 0.99,
                    perceptualPrecision: 0.98,
                    layout: .fixed(width: Self.width, height: 0),
                    traits: UITraitCollection(userInterfaceStyle: style),
                ),
                named: suffix,
            )
        }
    }
}

#endif
