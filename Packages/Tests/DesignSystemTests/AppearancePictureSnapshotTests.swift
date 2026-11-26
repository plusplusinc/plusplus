// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
@testable import DesignSystem

/// Settings' two looks as their card draws them. The card itself, its switches, and Void's row
/// coming and going are the app's (`AppearanceChoice`), which no snapshot reaches.
@Suite("Appearance pictures")
struct AppearancePictureSnapshotTests {
    /// Each tiny phone in its own look whatever the page's, the chosen one outlined and
    /// checked, and with Void on the dark phone true black. At AX5 the phones stop growing and
    /// the names grow.
    @Test("Light, and Dark chosen, plain and with Void")
    func pictures() {
        let pictures = VStack(spacing: Spacing.md) {
            ForEach([false, true], id: \.self) { isVoid in
                HStack(spacing: 0) {
                    AppearancePicture(.light, isChosen: false, isVoid: isVoid) { }
                        .frame(maxWidth: .infinity)
                    AppearancePicture(.dark, isChosen: true, isVoid: isVoid) { }
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(Spacing.md)
        .background(Color.pp(.surface))
        .padding(Spacing.md)
        .background(Color.pp(.background))
        assertThemedSnapshots(of: pictures, width: 390)
    }
}

#endif
