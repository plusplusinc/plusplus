import SwiftUI
import SwiftData

/// The cross-surface LANDING slots. A create made anywhere — Today's setup
/// step, a share import, the search field — lands on the list that owns that
/// type, which plays the entrance flash: ONE landing for every add (Dave,
/// 2026-07-23). The identity rides the slot rather than the notification, so a
/// list that isn't mounted yet can still consume it on first appear.
///
/// They live here, not in a view, because the surfaces that POST them and the
/// surface that CONSUMES them are now different files.

/// A routine added from ANOTHER tab (Today's setup step, a share import)
/// lands on the Routines list with the same entrance flash a same-tab add
/// gets — one landing for every add (Dave, 2026-07-23; the Today setup
/// flow used to land inside the new routine's detail instead). The uuid
/// is a HANDOFF SLOT, not a notification payload: the Routines tab may
/// not be mounted yet when the add happens (a first-run setup flow), so
/// the list consumes it on appear as well as on receive — whichever
/// fires first wins, and consuming clears the slot.
@MainActor
enum RoutineArrival {
    static var pending: UUID?

    /// Stamp the arrival and announce it: RootTabView switches to the
    /// Routines tab; a mounted list consumes immediately, an unmounted
    /// one on its first appear.
    static func land(_ uuid: UUID) {
        pending = uuid
        NotificationCenter.default.post(name: .plusplusRoutineArrived, object: nil)
    }
}

/// The cross-tab landing slots for an exercise/equipment created outside
/// its tab (the Find-or-create surface) — `RoutineArrival`'s twins, one
/// landing for every add (no toasts; the list + entrance flash IS the
/// feedback). The identity is a SAVED model's `PersistentIdentifier`
/// (permanent once saved — the temp→permanent swap happens at first
/// save, and every landing path saves synchronously before posting);
/// the slot drives scroll + flash identity only, never navigation.
@MainActor
enum ExerciseArrival {
    static var pending: PersistentIdentifier?

    static func land(_ id: PersistentIdentifier) {
        pending = id
        NotificationCenter.default.post(name: .plusplusExerciseArrived, object: nil)
    }
}

@MainActor
enum EquipmentArrival {
    static var pending: PersistentIdentifier?

    static func land(_ id: PersistentIdentifier) {
        pending = id
        NotificationCenter.default.post(name: .plusplusEquipmentArrived, object: nil)
    }
}
