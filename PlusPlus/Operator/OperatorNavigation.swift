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

    /// Stamp the destination and announce it: RootTabView switches to the tab
    /// that owns it, and that tab root does the pushing.
    ///
    /// The stamp is what makes the routine push survive a tab that isn't
    /// mounted yet (2026-07-26). A tab's content is built when it is first
    /// selected, so a notification alone reaches nobody when the Browse tab
    /// has never been visited — the push would be a silent no-op, the failure
    /// class the build-76 dead taps came from. The slot waits for the tab
    /// instead, which is the `RoutineArrival` handoff exactly.
    @MainActor
    static func show(_ destination: OperatorDestination) {
        if case .routine(let uuid) = destination { OperatorArrival.pendingRoutine = uuid }
        NotificationCenter.default.post(name: .plusplusOperatorShow, object: destination)
    }
}

/// The waiting room for an Operator outcome's push — see `OperatorDestination.show`.
@MainActor
enum OperatorArrival {
    static var pendingRoutine: UUID?

    /// Take the pending routine, if any. Consuming clears it, so exactly one
    /// surface pushes however many are listening.
    static func takeRoutine() -> UUID? {
        defer { pendingRoutine = nil }
        return pendingRoutine
    }
}

extension Notification.Name {
    /// Posted by Operator when an outcome should be shown on the main
    /// surface (the `.plusplusStartRoutine` precedent): RootTabView
    /// switches tabs; the owning tab root resolves and pushes. Wired in
    /// the chat-surface PR; defined here so receipts can carry
    /// destinations from day one.
    static let plusplusOperatorShow = Notification.Name("plusplusOperatorShow")
}
