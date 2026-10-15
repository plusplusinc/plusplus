/// The values a plan can hold. They bound stepping and typing, and a stored value outside them
/// reads as the default.
enum PlanLimits {
    static let sets = 1 ... 99
    static let reps = 1 ... 999
    /// Up to 99:59. Typing allows 1 s; stepping stops at 5 s.
    static let seconds = 1 ... 5999
    static let maxWeight = 9999.0
}
