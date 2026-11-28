/// Which way a stepper moves a value, one step up or down. How far a step goes is the value's
/// own (a set, 5 s, a load's step), so a direction carries no size.
public enum StepDirection: Sendable, Hashable {
    case up
    case down
}
