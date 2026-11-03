import Foundation

// A superset's own gaps: the switch from one member to the next within a round, the rest after a
// round, and the transition after the last round. Every member holds the same values, as they
// hold one round count, each nil until stepped: nil reads as the default or, for the rest after a
// round, as derived from the members' own rests.

/// A superset's gap, as its sheet steps it.
public enum RoundPart: Sendable {
    /// Between one member's set and the next member's, within a round.
    case switchPartners
    /// After a round's last member, before the next round.
    case afterRound
    /// After the last round, before the next exercise.
    case transition
}

extension RoundRest {
    subscript(part: RoundPart) -> Int? {
        get {
            switch part {
            case .switchPartners: switchPartners
            case .afterRound: afterRound
            case .transition: transition
            }
        }
        set {
            switch part {
            case .switchPartners: switchPartners = newValue
            case .afterRound: afterRound = newValue
            case .transition: transition = newValue
            }
        }
    }

    /// This one's values, each it never set taken from the first of `others` that set it, so a
    /// value set on any member of rows that join wins over an empty one.
    func filled(from others: some Sequence<RoundRest>) -> RoundRest {
        var filled = self
        for other in others {
            for part in [RoundPart.switchPartners, .afterRound, .transition] where filled[part] == nil {
                filled[part] = other[part]
            }
        }
        return filled
    }
}

extension RoundPart {
    /// "Switch", "Rest after round", "Transition".
    public var label: String {
        switch self {
        case .switchPartners: "Switch"
        case .afterRound: "Rest after round"
        case .transition: "Transition"
        }
    }

    /// The switch moves 5 s a step, as a switch between sides; the others 15 s, as a rest.
    var step: Int {
        self == .switchPartners ? 5 : 15
    }
}

extension Routine {
    static let defaultRoundSwitch = 15
    static let defaultRoundTransition = 30

    /// A superset's gap for `id`'s superset, in seconds: the value set on its members, else the
    /// default, a 15 s switch and a 30 s transition, or the rest after a round derived from the
    /// members. Nil for a plain row.
    public func roundValue(_ part: RoundPart, of id: RoutineExercise.ID) -> Int? {
        guard let row = exercises.first(where: { $0.id == id }), row.supersetID != nil
        else { return nil }
        if let set = row.roundRest[part] {
            return set
        }
        return switch part {
        case .switchPartners: Self.defaultRoundSwitch
        case .afterRound: derivedRestAfterRound(of: id)
        case .transition: Self.defaultRoundTransition
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

    public func canStepRound(_ part: RoundPart, of id: RoutineExercise.ID, by direction: Int) -> Bool {
        steppedRound(part, of: id, by: direction) != nil
    }

    /// Moves a superset's gap a step, from what it reads now, and sets it on every member.
    public mutating func stepRound(_ part: RoundPart, of id: RoutineExercise.ID, by direction: Int) {
        guard let value = steppedRound(part, of: id, by: direction),
              let superset = exercises.first(where: { $0.id == id })?.supersetID
        else { return }
        for row in exercises.indices where exercises[row].supersetID == superset {
            exercises[row].roundRest[part] = value
        }
    }

    private func steppedRound(_ part: RoundPart, of id: RoutineExercise.ID, by direction: Int)
        -> Int?
    {
        roundValue(part, of: id)?.stepped(by: direction * part.step, within: PlanLimits.rest)
    }

    /// The rest after a round when none is set: the longest of the members' own rests, less a
    /// minute for what the others gave its muscles to recover, never under 30 s, or the whole of
    /// it when two members share a primary muscle; never more than the longest, so a superset of
    /// stretches rests none.
    private func derivedRestAfterRound(of id: RoutineExercise.ID) -> Int {
        guard let row = exercises.first(where: { $0.id == id }) else { return 0 }
        let members = [row] + partners(of: id)
        let longest = members.map(\.plan.rest).max() ?? 0
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
