/// The values a stored plan can hold; a stored value outside them reads as the default. Wider
/// than the sheet's wheels, so a value saved by an earlier version still loads as it was.
enum PlanLimits {
    static let sets = 1 ... 99
    static let reps = 1 ... 999
    /// Up to 99:59.
    static let seconds = 1 ... 5999
}
