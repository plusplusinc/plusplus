import Foundation
import PlusPlusKit

/// This calendar week's plan-vs-done counts — the week block bar's
/// inputs (Quiet Arcade), shared by Today's header and the finish
/// screen so the two can't disagree. Planned sums every schedule's
/// weekly expectation (empty routines included: the schedule is a
/// fact even while the routine can't start); completed counts every
/// session finished this week, scheduled or not — work done is work
/// done, and the caption stays honest when it outruns the plan.
enum WeekPlan {
    static func counts(
        routines: [Routine],
        sessions: [WorkoutSession],
        today: Date,
        calendar: Calendar
    ) -> (completed: Int, planned: Int) {
        let planned = routines.reduce(0) { $0 + $1.schedule.normalized.expectedSessionsPerWeek }
        guard planned > 0, let week = calendar.dateInterval(of: .weekOfYear, for: today) else {
            return (0, planned)
        }
        let completed = sessions.reduce(0) { count, session in
            guard let ended = session.endedAt, week.contains(ended) else { return count }
            return count + 1
        }
        return (completed, planned)
    }
}
