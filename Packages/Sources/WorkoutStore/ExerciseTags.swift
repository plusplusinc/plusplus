/// What an exercise does, in a small fixed vocabulary, finer than its muscle group, so a routine
/// can be named for what it is. Internal words: a name never uses them as they are ("hinge").
struct ExerciseTags: Equatable, Sendable {
    /// Nil for a stretch, and for anything none of the patterns fits (a calf raise).
    let movement: Movement?
    /// What the exercise mostly works.
    let primary: Set<Muscle>
    /// What it works along the way.
    let secondary: Set<Muscle>
    let kind: Kind

    init(
        _ movement: Movement?,
        _ primary: Set<Muscle>,
        _ secondary: Set<Muscle> = [],
        _ kind: Kind = .strength,
    ) {
        self.movement = movement
        self.primary = primary
        self.secondary = secondary
        self.kind = kind
    }

    /// An exercise someone made: nothing known beyond its group.
    static let none = Self(nil, [])

    enum Movement: Sendable {
        case push
        case pull
        case squat
        case hinge
        case lunge
        case carry
        case rotation
        case hold
    }

    /// Declared from the top of the body down, the order a name lists them in.
    enum Muscle: CaseIterable, Sendable {
        case chest
        case lats
        case upperBack
        case frontDelts
        case sideDelts
        case rearDelts
        case biceps
        case triceps
        case forearms
        case abs
        case obliques
        case lowerBack
        case hipFlexors
        case glutes
        case quads
        case hamstrings
        case calves
    }

    enum Kind: Sendable {
        case strength
        /// A stretch or mobility drill.
        case stretch
        case balance
        /// Work for the heart and lungs as much as the muscles.
        case conditioning
    }
}

extension Exercise {
    /// A stretch or mobility drill rather than strength work, so a routine of them is named for
    /// what it is.
    var isStretch: Bool {
        tags.kind == .stretch
    }
}
