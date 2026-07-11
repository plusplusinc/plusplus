import Foundation
import SwiftData

/// A named, curated equipment list — one per training context (Home,
/// Hotel, the office rack). Exactly one library is ACTIVE at a time and
/// every "what gear do I have?" read in the app resolves through the
/// active one: catalog filtering, template gear verdicts, "needs X"
/// cues, the populate offer. Libraries share the same `Equipment`
/// records, so weight steps and suggested metric profiles follow the
/// gear between contexts. New libraries start EMPTY by design — the
/// value is a curated short list of what you'd actually use there, not
/// a transcript of everything the building contains.
@Model
final class EquipmentLibrary {
    var name: String
    var order: Int
    /// Stable identity for the active-library pointer: persistentModelID
    /// re-keys at the first save of a fresh model (the
    /// fullScreenCover(item:) law), so the pointer stores this instead.
    var uuid: UUID
    /// Explicit inverse declared here (see Equipment.libraries) — every
    /// relationship declares its inverse; unidirectional to-manys are
    /// where store integrity frays (#186/#196).
    @Relationship(inverse: \Equipment.libraries)
    var equipment: [Equipment]? = []

    init(name: String, order: Int) {
        self.name = name
        self.order = order
        self.uuid = UUID()
    }
}

extension EquipmentLibrary {
    /// UserDefaults key for the active-library pointer. Device-local on
    /// purpose: which gear you have with you is a property of the
    /// device's whereabouts, not of the training data.
    static let activeIDKey = "activeEquipmentLibraryID"

    /// The migration folds the legacy single-library state into this.
    static let defaultName = "Home"

    /// Resolve the active library from an already-fetched list. Views
    /// pass their @AppStorage value as `storedID` so switching re-renders
    /// them; a pointer that matches nothing (stale UUID, fresh install)
    /// falls back to the first library by order. The fallback never
    /// writes the pointer — only explicit switches do, so parallel test
    /// suites sharing UserDefaults can't fight over it.
    static func active(in libraries: [EquipmentLibrary], storedID: String? = nil) -> EquipmentLibrary? {
        let sorted = libraries.sorted { ($0.order, $0.name) < ($1.order, $1.name) }
        let id = storedID ?? UserDefaults.standard.string(forKey: activeIDKey)
        if let id, !id.isEmpty, let match = sorted.first(where: { $0.uuid.uuidString == id }) {
            return match
        }
        return sorted.first
    }

    /// Non-view resolution (SeedData's populate math, the importer).
    static func active(context: ModelContext) -> EquipmentLibrary? {
        let all = (try? context.fetch(FetchDescriptor<EquipmentLibrary>())) ?? []
        return active(in: all)
    }

    static func makeActive(_ library: EquipmentLibrary) {
        UserDefaults.standard.set(library.uuid.uuidString, forKey: activeIDKey)
    }

    /// Members with just-deleted gear filtered out (the lingering-
    /// reference rule from ExerciseFilterState, bug hunt B1).
    var members: [Equipment] {
        (equipment ?? []).filter { !$0.isDeleted }
    }

    var memberNames: Set<String> {
        Set(members.map(\.name))
    }

    func contains(_ item: Equipment) -> Bool {
        members.contains { $0 === item }
    }

    func setMembership(_ item: Equipment, _ included: Bool) {
        if included {
            guard !contains(item) else { return }
            equipment = (equipment ?? []) + [item]
        } else {
            equipment?.removeAll { $0 === item }
        }
    }
}
