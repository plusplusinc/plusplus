import DesignSystem
import WorkoutStore

/// What a row draws of the workout: its set bars, its rest between sets in its figures' slot,
/// the rest after it, under it, a superset round's rest before it, above it, whether it is
/// finished, its equipment while it is next after a rest, and on the current exercise what
/// follows its set.
struct RowParts {
    let bars: SetProgress?
    let restBetween: SetRest?
    let restAfter: RestBlock
    let restBefore: RestBlock
    let isDone: Bool
    let nextUp: [String]?
    let after: String?
}
