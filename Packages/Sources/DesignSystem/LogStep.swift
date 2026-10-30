/// The slide that logs the current exercise's set: what it says, how firm its haptic is, and
/// what it does.
public struct LogStep {
    public var label: String
    public var weight: SlideToLog.Weight
    /// Logs the set, as the slide commits.
    public var action: () -> Void
    /// Once the key is back at the start after a log (`SlideToLog`'s `onReturn`).
    public var onReturn: () -> Void

    public init(
        label: String,
        weight: SlideToLog.Weight = .set,
        action: @escaping () -> Void,
        onReturn: @escaping () -> Void = { },
    ) {
        self.label = label
        self.weight = weight
        self.action = action
        self.onReturn = onReturn
    }

    /// Logs the set with no slide, as VoiceOver's action does: the key never leaves the start.
    public func logAtOnce() {
        action()
        onReturn()
    }
}
