import Foundation

// A superset's own rest, after each round, the last included, which is the way to the next
// exercise. Going from one member to the next takes no time. Every member holds the same value, as
// they hold one round count, nil until stepped: nil reads as derived from the members' own rests.

/// A superset's gap, as its sheet steps it.
public enum RoundPart: Sendable {
    /// After each round.
    case afterRound
}

extension RoundRest {
    subscript(part: RoundPart) -> Int? {
        get {
            switch part {
            case .afterRound: afterRound
            }
        }
        set {
            switch part {
            case .afterRound: afterRound = newValue
            }
        }
    }

    /// This one, or, while it is automatic, the first of `others` set by hand, so a value set
    /// on any member of rows that join wins over an automatic one; a value kept for later is
    /// taken from the first that has one.
    func filled(from others: some Sequence<RoundRest>) -> RoundRest {
        guard isAuto else { return self }
        let others = Array(others)
        if let set = others.first(where: { !$0.isAuto }) {
            return set
        }
        return RoundRest(afterRound: afterRound ?? others.lazy.compactMap(\.afterRound).first)
    }
}

extension RoundPart {
    /// "Rest".
    public var label: String {
        switch self {
        case .afterRound: "Rest"
        }
    }
}

extension Routine {
    /// A superset's gap for `id`'s superset, in seconds: the value set on its members, else the
    /// rest after a round derived from the members. Nil for a plain row.
    public func roundValue(_ part: RoundPart, of id: RoutineExercise.ID) -> Int? {
        guard let row = exercises.first(where: { $0.id == id }), row.supersetID != nil
        else { return nil }
        if !row.roundRest.isAuto, let set = row.roundRest[part] {
            return set
        }
        return switch part {
        case .afterRound: derivedRestAfterRound(of: id)
        }
    }

    /// "None", "15 s", "2:30 min"; empty for a plain row.
    public func roundText(_ part: RoundPart, of id: RoutineExercise.ID, locale: Locale = .current)
        -> String
    {
        roundValue(part, of: id).map { RoutineExercise.gapText($0, locale: locale) } ?? ""
    }

    /// The gap in words, for VoiceOver.
    public func spokenRoundText(
        _ part: RoundPart,
        of id: RoutineExercise.ID,
        locale: Locale = .current,
    ) -> String {
        roundValue(part, of: id).map { RoutineExercise.spokenGap($0, locale: locale) } ?? ""
    }

    public func canStepRound(
        _ part: RoundPart,
        of id: RoutineExercise.ID,
        by direction: Int,
    ) -> Bool {
        steppedRound(part, of: id, by: direction) != nil
    }

    /// Moves a superset's gap a step, from what it reads now, and sets it on every member.
    public mutating func stepRound(
        _ part: RoundPart,
        of id: RoutineExercise.ID,
        by direction: Int,
    ) {
        guard let value = steppedRound(part, of: id, by: direction),
              let superset = exercises.first(where: { $0.id == id })?.supersetID
        else { return }
        for row in exercises.indices where exercises[row].supersetID == superset {
            exercises[row].roundRest[part] = value
            exercises[row].roundRest.isAuto = false
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
        guard let superset = exercises.first(where: { $0.id == id })?.supersetID else { return }
        var shared = exercises.first { $0.id == id }?.roundRest ?? RoundRest()
        if !isAuto, shared.afterRound == nil {
            shared.afterRound = derivedRestAfterRound(of: id)
        }
        shared.isAuto = isAuto
        for row in exercises.indices where exercises[row].supersetID == superset {
            exercises[row].roundRest = shared
        }
    }

    private func steppedRound(_ part: RoundPart, of id: RoutineExercise.ID, by direction: Int)
        -> Int?
    {
        // 15 s a step, as a rest between sets.
        roundValue(part, of: id)?.stepped(by: direction * 15, within: PlanLimits.rest)
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
    /// Gives the rows at `indices` one superset's gaps: `source`'s, each it never set taken from
    /// the first of the rows that set it.
    mutating func shareRoundRest(_ source: RoundRest, over indices: some Collection<Int>) {
        let shared = source.filled(from: indices.map { self[$0].roundRest })
        for row in indices {
            self[row].roundRest = shared
        }
    }
}
