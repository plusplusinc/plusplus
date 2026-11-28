/// The values a stored plan can hold; a stored value outside them reads as the default. A
/// stepper stays within them too. Every range is of `Int`s but the weight's, so a stored value
/// is checked through the labeled `holds`, which says which range it is meant for.
enum PlanLimits {
    static let sets = 1 ... 99
    static let reps = 1 ... 999
    /// A timed set's time, in seconds: up to 99:59.
    static let seconds = 1 ... 5999
    /// In the weight's own unit, ending on a value every step lands on: 5 lb, 2 kg, 2.5 kg.
    static let weight = 1.0 ... 1000.0
    /// A rest, in seconds: none to 10 min.
    static let rest = 0 ... 600
    /// A rest's step, a row's or a superset's.
    static let restStep = 15

    static func holds(sets count: Int) -> Bool {
        sets.contains(count)
    }

    static func holds(reps count: Int) -> Bool {
        reps.contains(count)
    }

    /// Whether a timed set's time is one a plan holds.
    static func holds(seconds time: Int) -> Bool {
        seconds.contains(time)
    }

    static func holds(weight amount: Double) -> Bool {
        weight.contains(amount)
    }

    /// Whether a rest, in seconds, is one a plan holds.
    static func holds(rest seconds: Int) -> Bool {
        rest.contains(seconds)
    }
}
