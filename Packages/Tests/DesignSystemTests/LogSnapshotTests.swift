// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import Foundation
import SwiftUI
import Testing
@testable import DesignSystem

/// Log's tabs and an opened logged workout, built from the components `LogScreen` and
/// `LoggedWorkoutScreen` compose them from. The screens live in the app, which has no test
/// target; their bars and segmented control are system chrome, checked on the simulator.
@Suite("Log")
struct LogSnapshotTests {
    private static let screenWidth: CGFloat = 390

    /// Four weeks starting on a Sunday, today the 27th square, the days after it hidden.
    private static func weeks(done: Set<Int>) -> [[DayGrid.Square]] {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        return (0 ..< 4).map { week in
            (0 ..< 7).map { day in
                let index = week * 7 + day
                return DayGrid.Square(
                    id: start.addingTimeInterval(Double(index) * 86400),
                    isDone: done.contains(index),
                    isToday: index == 26,
                    isShown: index <= 26,
                    spoken: "Day \(index)",
                )
            }
        }
    }

    private static let initials = ["S", "M", "T", "W", "T", "F", "S"]

    /// A tab's first line, in secondary text.
    private func line(_ text: String) -> some View {
        Text(text)
            .font(.ppRowDetail)
            .foregroundStyle(.pp(.textSecondary))
    }

    private func screen(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .background(Color.pp(.background))
    }

    /// History's top, as `LogScreen.historyTab` lays it out.
    private func historyTop(count: String, done: Set<Int>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                line("Since Oct 25")
                Spacer(minLength: Spacing.sm)
                Text(count)
                    .font(.ppRowDetail)
                    .foregroundStyle(.pp(.done))
            }
            .padding(.bottom, Spacing.md)
            DayGrid(initials: Self.initials, weeks: Self.weeks(done: done))
                .padding(.bottom, Spacing.md)
        }
    }

    @Test("History: the period's calendar, today outlined, then each workout, a long name wrapping")
    func history() {
        let view = screen {
            historyTop(count: "4", done: [5, 12, 19, 24, 26])
            ForEach(
                [
                    ("Upper body", "Sat, Nov 21 · 51 min"),
                    (
                        "Legs, core, and a long finisher of carries and sled pushes",
                        "Thu, Nov 19 · 44 min",
                    ),
                    ("New workout", "Tue, Nov 17 · 22 min"),
                ],
                id: \.0,
            ) { name, detail in
                LogRow(name, detail: detail, spoken: name)
                    .overlay(alignment: .bottom) { RowLine() }
            }
        }
        assertThemedSnapshots(of: view, width: Self.screenWidth)
    }

    @Test("History with nothing logged: the empty calendar, its line, and Go to Workouts")
    func emptyHistory() {
        let view = screen {
            historyTop(count: "0", done: [])
            VStack(spacing: Spacing.md) {
                line("Today is a good day to go from 0 to 1.")
                    .multilineTextAlignment(.center)
                Button("Go to Workouts") { }
                    .buttonStyle(.pill)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xl)
        }
        assertThemedSnapshots(of: view, width: Self.screenWidth)
    }

    @Test("A workout opened, or Diff: a gain in green, Same, First time, a drop, and a note")
    func exercises() {
        let view = screen {
            LogRow(
                "Dumbbell bench press",
                tag: .gain("+5 lb"),
                figures: "10 × 30 lb/side · 10 × 30 lb/side · 10 × 30 lb/side",
                spoken: "Dumbbell bench press",
            )
            .overlay(alignment: .bottom) { RowLine() }
            LogRow(
                "Barbell back squat",
                tag: .quiet("Same"),
                figures: "5 × 185 lb → 5 × 185 lb",
                spoken: "Barbell back squat",
            )
            .overlay(alignment: .bottom) { RowLine() }
            LogRow(
                "Chin-up",
                tag: .quiet("First time"),
                figures: "6 · 6",
                spoken: "Chin-up",
            )
            .overlay(alignment: .bottom) { RowLine() }
            LogRow(
                "Side plank",
                tag: .quiet("\u{2212}0:05"),
                figures: "0:40/0:45 · 0:45/0:45",
                detail: "Per side. Set 1 planned at 0:45.",
                spoken: "Side plank",
            )
            .overlay(alignment: .bottom) { RowLine() }
        }
        assertThemedSnapshots(of: view, width: Self.screenWidth)
    }

    @Test("Gaps: six groups fewest first, a bar each, the missed ones at full strength")
    func gaps() {
        // Core and Arms have had no set in two weeks.
        let groups: KeyValuePairs = [
            "Core": 0, "Arms": 3, "Shoulders": 6, "Back": 11, "Chest": 14, "Legs": 20,
        ]
        let view = screen {
            line("Sets since Oct 25")
                .padding(.bottom, Spacing.sm)
            ForEach(groups, id: \.key) { name, sets in
                CountRow(
                    name,
                    count: "\(sets)",
                    fraction: Double(sets) / 20,
                    isStressed: sets < 5,
                    spoken: name,
                )
            }
        }
        assertThemedSnapshots(of: view, width: Self.screenWidth)
    }
}

#endif
