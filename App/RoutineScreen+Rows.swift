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
            rest: parts?.restAfter ?? .closed,
            restAbove: parts?.restBefore ?? .closed,
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
        let rest = drawnRestBlock()
        return routine.exercises.reduce(into: [:]) { parts, item in
            parts[item.id] = RowParts(
                bars: bars[item.id],
                restBetween: setWait(of: item.id, current: current),
                restAfter: rest?.block(in: item.id, above: false) ?? .closed,
                restBefore: rest?.block(in: item.id, above: true) ?? .closed,
                isDone: finished.contains(item.id),
                nextUp: item.id == nextUp ? [item.exercise].equipment.map(\.name) : nil,
                after: item.id == current ? after : nil,
            )
        }
    }

    /// The current exercise's content as it will rest once its set in progress has moved the
    /// workout off it, with no rest open around it: its bars one set on, or, with that set its
    /// last, done and with none. What a move off it lands by, as it shrinks to this
    /// (`reportingRailPitch(isOn:of:to:)`): at accessibility sizes the bars take a line of their
    /// own.
    func restingContent(_ item: RoutineExercise, in shown: LiveWorkout?) -> some View {
        let progress = shown?.bars(of: item.id).map { (done: $0.done + 1, total: $0.total) }
        let isDone = progress.map { $0.done >= $0.total } ?? false
        return LabelWithRest(
            label: RowLabel(
                title: item.exercise.name,
                detail: item.detailParts(locale: locale),
                bars: isDone ? nil : progress.map {
                    SetProgress(
                        done: $0.done,
                        total: $0.total,
                        spoken: spokenProgress(done: $0.done, total: $0.total, locale: locale),
                    )
                },
                isDone: isDone,
            ),
            rest: .closed,
        )
    }

    /// Whether `id`'s row measures its pitch at rest from a hidden copy of it
    /// (`restingContent(_:in:)`): the current exercise, while it stands grown. Measured, not noted
    /// from the row before it grew, since a screen made with the workout under way, as the app
    /// reopening into one and Start on a routine opened from Workouts both make, never saw that
    /// row at rest: with no pitch, a move off it landed the next row as the shift ended, in a
    /// second motion. Not while Start grows it or a move is under way, when nothing reads it and
    /// the copy would only be laid out again on every frame.
    func notesRestingPitch(of id: RoutineExercise.ID, current: RoutineExercise.ID?) -> Bool {
        id == current && !isStarting && !isMovingOn
    }

    /// Scrolls the current exercise's row up to just under the bar.
    func scrollToCurrent() {
        if let place = currentPlace {
            scrollPosition.scrollTo(y: place.landingY)
        }
    }
}
