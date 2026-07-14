import Foundation
import SwiftData

/// Presentation/navigation identity for the routine-family models keys on
/// the model's stable `uuid`, never `persistentModelID` — the latter swaps
/// temporary→permanent at a fresh model's first save and re-keys an open
/// sheet/push (the tray-flicker class). These tiny value wrappers carry a
/// `uuid` across a `.sheet(item:)` / `.navigationDestination` boundary; the
/// model is resolved back at the destination.

/// A sheet item keyed on a model's `uuid`. Used wherever a `.sheet(item:)`
/// used to bind a `@Model` directly.
struct IdentifiedUUID: Identifiable, Hashable {
    let id: UUID
}

/// A navigation value for pushing a `Routine` by its stable id. Registered
/// with `.navigationDestination(for: RoutineRef.self)` at each stack root;
/// the routine is resolved from the id in the destination.
struct RoutineRef: Hashable {
    let uuid: UUID
}

extension ModelContext {
    /// Resolve a live `Routine` by its stable `uuid`. A direct fetch (not a
    /// `@Query`-list lookup) so a just-created routine resolves immediately,
    /// with no one-frame lag before the query refreshes.
    func routine(uuid: UUID) -> Routine? {
        let descriptor = FetchDescriptor<Routine>(predicate: #Predicate { $0.uuid == uuid })
        return (try? fetch(descriptor))?.first
    }
}
