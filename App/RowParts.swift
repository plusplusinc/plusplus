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
    let after: CaptionEnd?
}

/// What follows a set at the end of the current exercise's caption line, "then rest 1:00", and
/// in words for VoiceOver, "then rest 1 minute".
struct CaptionEnd: Equatable {
    let text: String
    let spoken: String
}
