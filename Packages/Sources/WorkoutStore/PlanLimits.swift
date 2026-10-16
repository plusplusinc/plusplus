/// The values a stored plan can hold; a stored value outside them reads as the default. A
/// stepper stays within them too.
enum PlanLimits {
    static let sets = 1 ... 99
    static let reps = 1 ... 999
    /// Up to 99:59.
    static let seconds = 1 ... 5999
    /// In the weight's own unit, ending on a value every step lands on: 5 lb, 2 kg, 2.5 kg.
    static let weight = 1.0 ... 1000.0
}
