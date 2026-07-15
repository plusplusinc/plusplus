import Foundation

/// Where an Operator action's outcome lives — the receipt card's "View"
/// destination, and (once the change engine applies something while the
/// drawer is up) the screen the main surface is steered to behind it.
/// Routines get the full uuid-keyed push (the ModelRefs pathway);
/// exercises and equipment are tab-level in v1 — their navigation has no
/// uuid pathway yet, and inventing one is a separate decision.
enum OperatorDestination: Equatable, Codable {
    case today
    case routine(UUID)
    case exercisesTab
    case equipmentTab
}

extension Notification.Name {
    /// Posted by Operator when an outcome should be shown on the main
    /// surface (the `.plusplusStartRoutine` precedent): RootTabView
    /// switches tabs; the owning tab root resolves and pushes. Wired in
    /// the chat-surface PR; defined here so receipts can carry
    /// destinations from day one.
    static let plusplusOperatorShow = Notification.Name("plusplusOperatorShow")
}
