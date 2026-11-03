import Foundation

// The rest a row's list line reads, under its plan.

extension Routine {
    /// The rest a row's list line shows, in seconds: a plain row's rest between sets, when it has
    /// more than one set and a rest at all; nil otherwise, and on a superset's member.
    public func shownRest(of id: RoutineExercise.ID) -> Int? {
        guard let row = exercises.first(where: { $0.id == id }), row.supersetID == nil,
              row.plan.sets > 1, row.plan.rest > 0
        else { return nil }
        return row.plan.rest
    }

    /// The rest line under a row's plan, "3 min rest", "90 s rest", or nil for none.
    public func restLine(of id: RoutineExercise.ID, locale: Locale = .current) -> String? {
        shownRest(of: id).map { TimeText.text(seconds: $0, locale: locale) + " rest" }
    }
}
