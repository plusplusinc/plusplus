// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
@testable import DesignSystem

/// Log's prompt to sync to Apple Health on the screen's ground, and the note that takes its
/// place: unfilled, as with Reduce Motion or VoiceOver, and its OK partway filled, its label
/// switching color where the fill's edge crosses it. At AX5 neither clips, and the note's
/// no-break spaces still wrap beside its OK.
@Suite("Prompt row snapshots")
struct PromptRowSnapshotTests {
    private static let width: CGFloat = 390
    private static let note =
        "You can enable sync later in PlusPlus\u{A0}Settings\u{A0}›\u{A0}Apple\u{A0}Health."

    @Test("The prompt, its note unfilled, and its note with OK part filled")
    func prompt() {
        let view = VStack(spacing: Spacing.lg) {
            PromptRow("Sync to Apple Health", take: { }, dismiss: { })
            PromptNote(Self.note, held: nil)
            PromptNote(Self.note, held: KeyFill(length: 5, ends: .now, pausedLeft: 2.5))
        }
        .padding(Spacing.md)
        .background(Color.pp(.background))
        assertThemedSnapshots(of: view, width: Self.width)
    }
}

#endif
