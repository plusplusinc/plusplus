// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
@testable import DesignSystem

/// The slide that logs a set, at its moments: at rest with its arrow, partway with nothing
/// behind the key, past two-thirds still with its arrow, and resting at the end, after a log,
/// with the check. At AX5 the track and key grow with the text and "Log set" stays whole.
@Suite("Slide to log")
struct SlideToLogSnapshotTests {
    private static let width: CGFloat = 340

    @Test("An arrow at rest, partway, and past the commit; the check only resting at the end")
    func moments() {
        let moments = VStack(spacing: Spacing.md) {
            SlideToLog(progress: 0)
            SlideToLog(progress: 0.4)
            SlideToLog(progress: 0.75)
            SlideToLog("Log left", weight: .side, progress: 1, isFinishing: true)
        }
        .padding(Spacing.md)
        .background(Color.pp(.background))
        assertThemedSnapshots(of: moments, width: Self.width)
    }
}

#endif
