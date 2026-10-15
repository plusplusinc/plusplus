// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
@testable import DesignSystem

/// The title as a new suggestion arrives, drawn from the plain values `EditableTitle` works out
/// from its one clock: the old name fading out, the trail shuffling in blue behind the lead, and
/// the last letter easing to white. `typingFrame(of:at:)` gives each moment, so the images do
/// not depend on when they render; the `_` is held still rather than breathing.
@Suite("Editable title as a suggestion arrives")
struct SuggestionSnapshotTests {
    private static let screenWidth: CGFloat = 390
    private static let name = "Squat and pull"

    /// The title partway through `frame` of a suggestion typing in, or with none, the old
    /// suggestion `shown` at `opacity`.
    private func arriving(
        _ frame: TypingFrame? = nil,
        shown: String = name,
        opacity: Double = 1,
    ) -> some View {
        EditableTitleContent(
            draft: .constant(""),
            caret: Caret(),
            selection: .constant(nil),
            placeholder: Self.name,
            shownPlaceholder: frame?.shown ?? shown,
            isSuggested: true,
            placeholderOpacity: opacity,
            standIns: frame?.standIns ?? [:],
            tints: frame?.tints ?? [:],
            cursorTint: frame?.cursorTint ?? 1,
            isEditing: false,
            blinks: false,
            accessibilityLabel: "Routine name",
            accessibilityHint: "Renames the routine.",
            behavior: EmptyModifier(),
        )
        .padding(Spacing.md)
        .background(Color.pp(.background))
    }

    @Test("The old suggestion fades out under a blue _")
    func fadingOut() {
        assertThemedSnapshots(of: arriving(shown: "Leg day", opacity: 0.5), width: Self.screenWidth)
    }

    @Test("Behind the lead, two letters shuffle in blue and the landed ones ease to white")
    func typingTrail() {
        let lead = SuggestionTiming.leadInterval
        let frame = EditableTitle.typingFrame(of: Self.name, at: lead * 4 + lead / 2)
        assertThemedSnapshots(of: arriving(frame), width: Self.screenWidth)
    }

    @Test("The last letter and the _ ease from blue together")
    func lastLetterEasing() {
        let end = EditableTitle.typingDuration(of: Self.name)
        let frame = EditableTitle.typingFrame(
            of: Self.name,
            at: end - SuggestionTiming.tintFade / 2,
        )
        assertThemedSnapshots(of: arriving(frame), width: Self.screenWidth)
    }
}

#endif
