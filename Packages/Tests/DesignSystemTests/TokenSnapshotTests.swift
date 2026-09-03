// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import DesignSystem
import SwiftUI
import Testing

/// Visual regression coverage for the token palette.
///
/// A wrong light/dark pair is invisible in code review and obvious in an image, and a token
/// with no colorset behind it renders clear.
@Suite("Design tokens")
struct TokenSnapshotTests {
    private var paletteView: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(ColorToken.allCases, id: \.self) { token in
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(Color.pp(token))
                        .frame(width: 44, height: 28)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm)
                                .strokeBorder(Color.pp(.separator)),
                        )
                    // One line, shrunk to fit: wrapped text hyphenates with on-demand system
                    // dictionaries that CI machines may lack, which moves every line break.
                    Text(token.rawValue)
                        .font(.ppCaption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .foregroundStyle(.pp(.textPrimary))
                }
            }
        }
        .padding(Spacing.md)
        .background(Color.pp(.background))
    }

    @Test("Every token renders in light, dark, and XXXL")
    func palette() {
        assertThemedSnapshots(of: paletteView, width: 260)
    }
}

#endif
