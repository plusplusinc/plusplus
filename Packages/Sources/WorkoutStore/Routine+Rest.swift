import Foundation

// The rest a row's list line reads, under its plan.

extension Routine {
    /// The rest a row's list line shows, in seconds: a plain row's rest between sets, and on a
    /// superset's last member the rest after a round, when there is more than one set or round
    /// and a rest at all; nil otherwise, and on a superset's other members.
    public func shownRest(of id: RoutineExercise.ID) -> Int? {
        guard let index = exercises.firstIndex(where: { $0.id == id }),
              exercises[index].plan.sets > 1
        else { return nil }
        let rest: Int? = if let run = supersetRun(at: index) {
            index == run.upperBound ? roundValue(.afterRound, of: id) : nil
        } else {
            exercises[index].plan.rest
        }
        return rest.flatMap { $0 > 0 ? $0 : nil }
    }

    /// The rest line under a row's plan, "3 min rest", "90 s rest", or nil for none.
    public func restLine(of id: RoutineExercise.ID, locale: Locale = .current) -> String? {
        shownRest(of: id).map { TimeText.text(seconds: $0, locale: locale) + " rest" }
    }
}
