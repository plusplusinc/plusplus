import DesignSystem
import SwiftUI
import WorkoutStore

extension RoutineScreen {
    /// A row's content: its label, and under it its rest, as part of the row, so the row's own
    /// stretch of rail runs through the room it opens. A rest between sets, drawn inside the
    /// label, reads to VoiceOver as its own element after it (`SetRest.spoken`).
    func rowContent(
        _ item: RoutineExercise,
        current: RoutineExercise.ID?,
        on set: PlannedSet?,
        parts: RowParts?,
    ) -> some View {
        LabelWithRest(
            label: rowElement(rowLabel(item, current: current, on: set, parts: parts), of: item.id)
                .overlay(alignment: .bottom) { parts?.restBetween.map(\.spoken) },
            rest: parts?.restAfter ?? RestBlock(stage: .none, length: 0),
            restAbove: parts?.restBefore ?? RestBlock(stage: .none, length: 0),
            onRestHeight: { rowFrames.restHeights[item.id] = $0 },
        )
    }

    /// A row's label as VoiceOver reads it: a button that opens the row's sheet, with its
    /// superset as its value and its moves as actions. On the label alone, not the whole row, so
    /// a rest drawn in the row is its own element and no button.
    func rowElement(_ label: some View, of id: RoutineExercise.ID) -> some View {
        label
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(supersetValue(id))
            // None where it would do nothing: at an end, or with one row. None logs a set, on the
            // current exercise either: the key logs.
            .accessibilityActions {
                if let up = routine.slotMovingUp(id) {
                    Button("Move up") { step(id, to: up, wentUp: true) }
                }
                if let down = routine.slotMovingDown(id) {
                    Button("Move down") { step(id, to: down, wentUp: false) }
                }
                supersetActions(id)
            }
            .accessibilityIdentifier("routine.exercise")
    }

    /// Each row's bars, rests, and state in the workout, for the rows' closure to hold as values.
    /// Worked out in the closure, the rests read the stored workout live but the phase as the
    /// closure was made: a row redrawn on its own as a log was stored read the set in the workout
    /// with the phase from before the log, which hides it, and the last set's rest line went into
    /// the numbers' room for a pass, the rows below jumping up 24 pt as it came back out.
    func rowParts(
        in shown: LiveWorkout?,
        current: RoutineExercise.ID?,
    ) -> [RoutineExercise.ID: RowParts] {
        let bars = rowBars(in: shown)
        let finished = Set(shown?.finishedRows ?? [])
        let after = shown.flatMap { shown in
            shown.currentSet.flatMap { afterText(for: $0, in: shown) }
        }
        // Resting between two exercises, the next one grows a step once the rest shows, and
        // stays grown through the move out of the rest until it opens: dropped as the rest
        // ended, it shrank back and lost its equipment for a frame before growing again.
        let isRestingBetween = phase.drawnRest.map { !$0.isWithinExercise && $0.beat >= .shown }
            ?? (phase.move?.isFromRest == true)
        let nextUp = isRestingBetween ? shown?.currentSet?.row : nil
        return routine.exercises.reduce(into: [:]) { parts, item in
            parts[item.id] = RowParts(
                bars: bars[item.id],
                restBetween: setRest(of: item.id, current: current),
                restAfter: restBlock(in: item.id, above: false),
                restBefore: restBlock(in: item.id, above: true),
                isDone: finished.contains(item.id),
                nextUp: item.id == nextUp ? [item.exercise].equipment.map(\.name) : nil,
                after: item.id == current ? after : nil,
            )
        }
    }

    /// Scrolls the current exercise's row up to just under the bar.
    func scrollToCurrent() {
        if let place = currentPlace {
            scrollPosition.scrollTo(y: place.landingY)
        }
    }
}
