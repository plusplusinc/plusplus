import Foundation

// A superset's own rest, after each round, the last included, which is the way to the next
// exercise. Going from one member to the next takes no time. Every member holds the same value, as
// they hold one round count, Auto until stepped: derived from the members' own rests.

extension Rest {
    /// This one, or, while it is Auto, the first of `others` set by hand, so a value set on any
    /// member of rows that join wins over an automatic one; a value kept for later is taken from
    /// the first that has one.
    func filled(from others: [Rest]) -> Rest {
        guard case let .auto(kept) = self else { return self }
        return others.first { !$0.isAuto }
            ?? .auto(kept: kept ?? others.lazy.compactMap(\.lastByHand).first)
    }
}

extension Routine {
    /// The parts `id`'s sheet steps, in order: a plain row's plan, then its rest; a superset
    /// member's plan, then its superset's rest after each round, its own rest kept, unread, for
    /// when it leaves. Every row has a rest, a one-set row's and a one-round superset's too.
    public func sheetParts(of id: RoutineExercise.ID) -> [SheetPart] {
        guard let row = exercises.first(where: { $0.id == id }) else { return [] }
        let plan = row.exercise.planParts.map(SheetPart.plan)
        return plan + [row.supersetID == nil ? .plan(.rest) : .restAfterRound]
    }

    /// A superset's rest for `id`'s superset, in seconds: the value set on its members, else the
    /// rest after a round derived from the members. Nil for a plain row.
    public func restAfterRound(of id: RoutineExercise.ID) -> Int? {
        guard let row = exercises.first(where: { $0.id == id }), row.supersetID != nil
        else { return nil }
        return row.roundRest.seconds(derived: derivedRestAfterRound(of: id))
    }

    /// "None", "15 s", "2:30 min"; empty for a plain row.
    public func restAfterRoundText(of id: RoutineExercise.ID, locale: Locale = .current) -> String {
        restAfterRound(of: id).map { RoutineExercise.restText($0, locale: locale) } ?? ""
    }

    /// The rest in words, for VoiceOver.
    public func spokenRestAfterRound(of id: RoutineExercise.ID, locale: Locale = .current)
        -> String
    {
        restAfterRound(of: id).map { RoutineExercise.spokenRest($0, locale: locale) } ?? ""
    }

    public func canStepRestAfterRound(of id: RoutineExercise.ID, by direction: Int) -> Bool {
        restAfterRound(of: id)?.steppedRest(by: direction) != nil
    }

    /// Moves a superset's rest a step, from what it reads now, and sets it on every member.
    public mutating func stepRestAfterRound(of id: RoutineExercise.ID, by direction: Int) {
        guard let value = restAfterRound(of: id)?.steppedRest(by: direction),
              let superset = exercises.first(where: { $0.id == id })?.supersetID
        else { return }
        for row in exercises.indices where exercises[row].supersetID == superset {
            exercises[row].roundRest = .byHand(value)
        }
    }

    /// Whether `id`'s superset derives its rest from its members; false for a plain row.
    public func isRoundAuto(of id: RoutineExercise.ID) -> Bool {
        guard let row = exercises.first(where: { $0.id == id }), row.supersetID != nil
        else { return false }
        return row.roundRest.isAuto
    }

    /// Makes `id`'s superset derive its rest from its members (on), keeping the rest set by
    /// hand for later, or brings that back (off), or, if there is none, keeps the rest it reads
    /// now; on every member.
    public mutating func setRoundAuto(_ isAuto: Bool, of id: RoutineExercise.ID) {
        guard let row = exercises.first(where: { $0.id == id }), let superset = row.supersetID
        else { return }
        let shared = row.roundRest.settingAuto(isAuto, derived: derivedRestAfterRound(of: id))
        for row in exercises.indices where exercises[row].supersetID == superset {
            exercises[row].roundRest = shared
        }
    }

    /// The rest after a round when none is set: the longest of the members' own rests, less a
    /// minute for what the others gave its muscles to recover, never under 30 s, or the whole of
    /// it when two members share a primary muscle; never more than the longest, so a superset of
    /// stretches rests none.
    private func derivedRestAfterRound(of id: RoutineExercise.ID) -> Int {
        guard let row = exercises.first(where: { $0.id == id }) else { return 0 }
        let members = [row] + partners(of: id)
        let longest = members.map(\.rest).max() ?? 0
        let primaries = members.map(\.exercise.tags.primary)
        let sharesMuscle = primaries.indices.contains { first in
            primaries.indices.contains { second in
                first < second && !primaries[first].isDisjoint(with: primaries[second])
            }
        }
        return sharesMuscle ? longest : min(longest, max(longest - 60, 30))
    }
}

extension [RoutineExercise] {
    /// Gives the rows at `indices` one superset's rest: `source`'s, each it never set taken from
    /// the first of the rows that set it.
    mutating func shareRoundRest(_ source: Rest, over indices: some Collection<Int>) {
        let shared = source.filled(from: indices.map { self[$0].roundRest })
        for row in indices {
            self[row].roundRest = shared
        }
    }
}
