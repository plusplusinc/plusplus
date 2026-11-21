// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import DesignSystem
import SwiftUI
import Testing

/// A timed set in a workout, the current exercise over the keys at the bottom, as the routine
/// screen composes them, each held still (`pausedLeft`): "Starts in" over its count, the set's
/// time at the caption line's end, over "Start now"; the set's own count where the figures stand,
/// "then rest" at the line's end, over "Log early", gray, filling with purple from its leading
/// edge, its label dark over the purple and light over the gray, beside "+15 s"; and paused, the
/// count and the fill gray. At AX5, both keys' words whole.
@Suite("Timed set")
struct TimedSetSnapshotTests {
    private static let width: CGFloat = 390

    private struct Row: Identifiable {
        let id = UUID()
        let title: String
        let detail: [String]
        var focus: RowFocus?
        var bars: SetProgress?
        var setRest: SetRest?
    }

    /// The rows over `keys`, at the bottom as the bar puts them.
    private func screen(_ rows: [Row], keys: some View) -> some View {
        VStack(spacing: Spacing.lg) {
            Rail(rows, current: rows.first?.id) { row in
                RowLabel(
                    title: row.title,
                    detail: row.detail,
                    focus: row.focus,
                    bars: row.bars,
                    setRest: row.setRest,
                )
                .railRow()
            } end: {
                EmptyView()
            }
            keys
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pp(.background))
    }

    private static func plank(after: String?, side: String? = nil) -> RowFocus {
        RowFocus(
            place: SetPlace(word: "Set", number: 2, total: 3),
            side: side,
            figures: [.init(number: "30", unit: "sec")],
            spokenFigures: "30 seconds",
            after: after,
        )
    }

    private static let bars = SetProgress(done: 1, total: 3, spoken: "1 of 3 sets done")
    private let next = Row(title: "Push-up", detail: ["3 × 10 reps"])

    /// The set's own count, held with `left` of 30 seconds to go.
    private static func count(left: Double, isPaused: Bool = false) -> SetRest {
        SetRest(
            isRunning: true,
            length: 30,
            pausedLeft: left,
            turns: true,
            kind: .count,
            isPaused: isPaused,
        )
    }

    private func countKeys(left: Double, isPaused: Bool = false) -> some View {
        CountKeys(
            text: "Log early",
            filling: KeyFill(length: 30, ends: .now, pausedLeft: left, isPaused: isPaused),
            onKey: { },
            onExtend: { },
        )
    }

    @Test("Starts in: 0:10, the set's time beside the side though its rest wraps, and Start now")
    func startsIn() {
        var focus = Self.plank(after: "30 seconds", side: "Left")
        focus.place = SetPlace(word: "Round", number: 1, total: 3)
        focus.afterRoom = ["30 seconds", "then rest 0:30"]
        let plank = Row(
            title: "Side plank",
            detail: ["3 × 30s per side"],
            focus: focus,
            bars: Self.bars,
            setRest: SetRest(
                isRunning: true,
                length: 10,
                pausedLeft: 10,
                kind: .startsIn(time: "30 seconds"),
            ),
        )
        let key = Button("Start now") { }.buttonStyle(.primaryKey)
        assertThemedSnapshots(of: screen([plank, next], keys: key), width: Self.width)
    }

    @Test("Counting: the count in the figures' place, Log early filled across its label")
    func counting() {
        let plank = Row(
            title: "Plank",
            detail: ["3 × 30s"],
            focus: Self.plank(after: "then rest 0:30"),
            bars: Self.bars,
            setRest: Self.count(left: 15),
        )
        assertThemedSnapshots(
            of: screen([plank, next], keys: countKeys(left: 15)),
            width: Self.width,
        )
    }

    @Test("Nearly run out: Log early nearly full of purple")
    func nearlyFull() {
        let plank = Row(
            title: "Plank",
            detail: ["3 × 30s"],
            focus: Self.plank(after: "then rest 0:30"),
            bars: Self.bars,
            setRest: Self.count(left: 2),
        )
        assertThemedSnapshots(
            of: screen([plank, next], keys: countKeys(left: 2)),
            width: Self.width,
        )
    }

    @Test("Paused: the count and the key's fill gray")
    func paused() {
        let plank = Row(
            title: "Plank",
            detail: ["3 × 30s"],
            focus: Self.plank(after: "then rest 0:30"),
            bars: Self.bars,
            setRest: Self.count(left: 18, isPaused: true),
        )
        assertThemedSnapshots(
            of: screen([plank, next], keys: countKeys(left: 18, isPaused: true)),
            width: Self.width,
        )
    }

    @Test("One side at a time: the side beside the set, then rest at the line's end")
    func oneSide() {
        let sidePlank = Row(
            title: "Side plank",
            detail: ["3 × 30s per side"],
            focus: Self.plank(after: "then rest 0:30", side: "Right"),
            bars: Self.bars,
            setRest: Self.count(left: 20),
        )
        assertThemedSnapshots(
            of: screen([sidePlank, next], keys: countKeys(left: 20)),
            width: Self.width,
        )
    }
}

#endif
