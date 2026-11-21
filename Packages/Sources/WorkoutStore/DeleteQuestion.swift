import Foundation

/// What Delete asks before a created exercise goes, in its Customize form and in Add exercise's
/// hold menu: the workouts it will be removed from, by count, not by name (Used in has those),
/// then that workout history stays.
public enum DeleteQuestion {
    /// When the open workout, the one behind the sheet, uses the exercise, it is named first, as
    /// "this workout", and the others are counted after it (decided 2026-11-18); otherwise the
    /// workouts are counted. `workoutCount` counts every workout that uses it, the open one
    /// included.
    public static func message(workoutCount: Int, usedByOpenWorkout: Bool) -> String {
        let others = workoutCount - 1
        let workouts = if usedByOpenWorkout {
            switch others {
            case ...0: String(localized: "It will be removed from this workout.")
            case 1: String(localized: "It will be removed from this workout and 1 other.")
            default: String(localized: "It will be removed from this workout and \(others) others.")
            }
        } else {
            switch workoutCount {
            case ...0: String(localized: "No workout uses it.")
            case 1: String(localized: "It will be removed from the workout that uses it.")
            default: String(
                    localized: "It will be removed from the \(workoutCount) workouts that use it.",
                )
            }
        }
        return workouts + " " + String(localized: "Deleting doesn’t affect your workout history.")
    }
}
