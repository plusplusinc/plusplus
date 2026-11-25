// Runs only where UIKit exists, so `swift test` on macOS compiles it away and stays fast.
#if canImport(UIKit) && !os(watchOS)

import DesignSystem
import SwiftUI
import Testing

/// A workout's rests on the rail, as the workout screen composes them, each held still
/// (`pausedLeft`): before one, the current exercise saying the rest to follow; between two sets,
/// the rest in the figures' place, nothing under its count, over Skip rest part filled with
/// purple beside +15 s; between exercises, under the one done, the dot at its word, held at 0:18
/// so the round "0" leads and shows whole; paused there, the count white over Continue;
/// and in a superset with a round left, above its first member. With the workout list, a long
/// name on the lines it grows into.
@Suite("Rests")
struct RestSnapshotTests {
    private static let width: CGFloat = 390

    private struct Row: Identifiable {
        let id = UUID()
        let title: String
        let detail: [String]
        var focus: RowFocus?
        var bars: SetProgress?
        var setRest: SetRest?
        var isDone = false
        var nextUp: [String]?
        var rest = RestBlock(stage: .none, length: 0)
        var restAbove = RestBlock(stage: .none, length: 0)
    }

    private static let open = RestBlock(stage: .open, length: 90, pausedLeft: 62)

    /// The rest's keys at the bottom, Skip rest filled to where `left` of 90 seconds stands.
    private static func restKeys(left: Double) -> some View {
        CountKeys(
            text: "Skip rest",
            filling: KeyFill(length: 90, ends: .now, pausedLeft: left),
            spoken: .left,
            onKey: { },
            onExtend: { },
        )
    }

    /// `rows` on the rail, over `keys`, at the bottom as the bar puts them.
    private func screen(
        _ rows: [Row],
        restDot: UUID? = nil,
        current: UUID? = nil,
        keys: some View,
    ) -> some View {
        VStack(spacing: Spacing.lg) {
            rail(rows, current: current, restDot: restDot)
            keys.padding(.horizontal, Spacing.md)
        }
        .padding(.bottom, Spacing.md)
        .background(Color.pp(.background))
    }

    private func rail(
        _ rows: [Row],
        links: Set<UUID> = [],
        current: UUID? = nil,
        restDot: UUID? = nil,
    ) -> some View {
        Rail(
            rows,
            links: links,
            current: current,
            done: Set(rows.filter(\.isDone).map(\.id)),
            restDot: restDot,
        ) { row in
            LabelWithRest(
                label: RowLabel(
                    title: row.title,
                    detail: row.detail,
                    focus: row.focus,
                    bars: row.bars,
                    setRest: row.setRest,
                    isDone: row.isDone,
                    nextUp: row.nextUp,
                ),
                rest: row.rest,
                restAbove: row.restAbove,
            )
            .railRow()
        } end: {
            FloatingButtonRoom()
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pp(.background))
    }

    private static let figures: [RowFocus.Figure] = [
        .init(number: "10", unit: "reps"),
        .init(number: "25", unit: "lb/side"),
    ]

    private static func bench(
        set: Int,
        isDone: Bool = false,
        after: String? = nil,
    ) -> RowFocus {
        RowFocus(
            place: SetPlace(word: "Set", number: set, total: 3, isDone: isDone),
            equipment: ["Dumbbells", "Bench"],
            figures: figures,
            spokenFigures: "10 reps, 25 pounds per side",
            after: after,
        )
    }

    private let next = Row(title: "Push-up", detail: ["3 × 10 reps"])

    @Test("In a set: the rest to follow at the caption line's end")
    func currentInSet() {
        let current = Row(
            title: "Dumbbell bench press",
            detail: ["3 × 10 reps", "25 lb/side"],
            focus: Self.bench(set: 2, after: "then rest 1:30"),
            bars: SetProgress(done: 1, total: 3, spoken: "1 of 3 sets done"),
        )
        assertThemedSnapshots(of: rail([current, next], current: current.id), width: Self.width)
    }

    @Test("Between sets: Rest over the countdown in the figures' place, over Skip rest and +15 s")
    func betweenSets() {
        let current = Row(
            title: "Dumbbell bench press",
            detail: ["3 × 10 reps", "25 lb/side"],
            focus: Self.bench(set: 1, isDone: true),
            bars: SetProgress(done: 1, total: 3, spoken: "1 of 3 sets done"),
            setRest: SetRest(isRunning: true, length: 90, pausedLeft: 62),
        )
        assertThemedSnapshots(
            of: screen([current, next], current: current.id, keys: Self.restKeys(left: 62)),
            width: Self.width,
        )
    }

    /// The rest under the exercise done, before the next one, `left` seconds to go.
    private func betweenExercises(left: Double, isPaused: Bool = false) -> [Row] {
        let done = Row(
            title: "Dumbbell bench press",
            detail: ["3 × 10 reps", "25 lb/side"],
            isDone: true,
            rest: RestBlock(stage: .open, length: 90, pausedLeft: left, isPaused: isPaused),
        )
        let coming = Row(
            title: "Goblet squat",
            detail: ["3 × 10 reps", "35 lb"],
            nextUp: ["Kettlebell"],
        )
        return [done, coming, next]
    }

    @Test("Between exercises: under the one done, its first figure whole, the dot at its word")
    func betweenExercises() {
        let rows = betweenExercises(left: 18)
        assertThemedSnapshots(of: rail(rows, restDot: rows[0].id), width: Self.width)
    }

    @Test("Paused between exercises: the count white, Continue in the rest's keys' place")
    func paused() {
        let rows = betweenExercises(left: 62, isPaused: true)
        let key = Button("Continue") { }.buttonStyle(.primaryKey)
        assertThemedSnapshots(
            of: screen(rows, restDot: rows[0].id, keys: key),
            width: Self.width,
        )
    }

    @Test("A superset with a round left: the rest above its first member, the dot at its word")
    func supersetAbove() {
        let first = Row(
            title: "Dumbbell bench press",
            detail: ["3 × 10 reps", "25 lb/side"],
            bars: SetProgress(done: 1, total: 3, spoken: "1 of 3 sets done"),
            nextUp: ["Dumbbells", "Bench"],
            restAbove: Self.open,
        )
        let second = Row(
            title: "Pull-up",
            detail: ["3 × 6 reps"],
            bars: SetProgress(done: 1, total: 3, spoken: "1 of 3 sets done"),
        )
        assertThemedSnapshots(
            of: rail([first, second, next], links: [first.id], restDot: first.id),
            width: Self.width,
        )
    }

    @Test("A workout's list: a long name on the lines the current exercise's name breaks at")
    func wrappedNames() {
        let rows = [
            Row(title: "Cross-body shoulder stretch", detail: ["30s per side"]),
            Row(title: "Neutral-grip weighted pull-up with a pause", detail: ["3 × 6 reps"]),
            next,
        ]
        assertThemedSnapshots(of: rail(rows), width: Self.width)
    }
}

#endif
