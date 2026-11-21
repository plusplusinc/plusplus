// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// What VoiceOver reads for a timed set: landing on it during "Starts in", the exercise's label
/// says its name, set, and time, and that it starts in 10 seconds, with "Starts in" its own
/// element after it; once it counts, the count is "Time left", never "Rest"; and its keys are
/// "Log early", its value the seconds done, and "Plus 15 seconds".
@MainActor
@Suite("Timed set's accessibility")
struct TimedSetAccessibilityTests {
    private static let focus = RowFocus(
        place: SetPlace(word: "Set", number: 1, total: 3),
        figures: [.init(number: "30", unit: "sec")],
        spokenFigures: "30 seconds",
        after: "30 seconds",
    )

    /// The current exercise with `wait` in its figures' place, and the wait's own element after
    /// it, as the routine screen puts them.
    private func exercise(_ wait: SetRest, after: String? = nil) -> some View {
        var focus = Self.focus
        focus.after = after ?? focus.after
        return VStack {
            RowLabel(title: "Plank", detail: ["3 × 30s"], focus: focus, setRest: wait)
            wait.spoken
        }
        .frame(width: 402)
    }

    /// Each element in the tree, as "label: value": the label's own first, its parts after it
    /// (which its `children: .ignore` keeps VoiceOver from), the wait's element last.
    private func read(_ view: some View) throws -> [String] {
        try AccessibilityTree.nodes(of: view)
            .filter { $0.isAccessibilityElement && !$0.accessibilityElementsHidden }
            .map { node in
                [node.accessibilityLabel, node.accessibilityValue]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }
                    .joined(separator: ": ")
            }
    }

    @Test("Landing on Starts in: name, set, time, starts in 10 seconds, then Starts in's time")
    func startsIn() throws {
        let wait = SetRest(
            isRunning: true,
            length: 10,
            pausedLeft: 10,
            kind: .startsIn(time: "30 seconds"),
        )
        let read = try read(exercise(wait))
        #expect(read.first == "Plank, Set 1 of 3, 30 seconds, starts in 10 seconds")
        #expect(read.last == "Starts in: 10 seconds")
        #expect(!read.contains { $0.hasPrefix("Rest") }, "\(read)")
    }

    @Test("The set's own count reads as the time left, never as Rest")
    func counting() throws {
        let wait = SetRest(isRunning: true, length: 30, pausedLeft: 18, kind: .count)
        let read = try read(exercise(wait, after: "then rest 0:30"))
        #expect(read.first == "Plank, Set 1 of 3, then rest 0:30")
        #expect(read.last == "Time left: 18 seconds")
        #expect(!read.contains { $0.hasPrefix("Rest") }, "\(read)")
    }

    @Test("The keys are Log early, its value the seconds done, and Plus 15 seconds")
    func keys() throws {
        let keys = CountKeys(
            text: "Log early",
            filling: KeyFill(length: 30, ends: .now, pausedLeft: 18),
            onKey: { },
            onExtend: { },
        )
        let buttons = try AccessibilityTree.nodes(of: keys.frame(width: 402))
            .filter { $0.accessibilityTraits.contains(.button) }
        #expect(buttons.map(\.accessibilityLabel) == ["Log early", "Plus 15 seconds"])
        #expect(buttons.first?.accessibilityValue == "12 of 30 seconds done")
    }
}

#endif
