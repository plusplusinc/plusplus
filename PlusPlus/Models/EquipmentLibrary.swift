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
    /// `main` since 2026-07-17 (the git wink; activity-neutral where
    /// "Home" wasn't) — `SeedData.renameDefaultKitIfNeeded` upgrades an
    /// existing store's lone untouched "Home".
    static let defaultName = "main"

    /// The baked-in no-equipment kit (2026-07-21, Dave): every store always
    /// carries this alongside `main`, so a bodyweight-only scope is always one
    /// tap away and nobody has to build one. `null` is the programmer wink (the
    /// empty set, pairs with `main` and the `++` mark); an empty membership
    /// already means bodyweight-only. Identity is the reserved NAME — the
    /// interchange merges libraries by name, so seed/export/import all dedup on
    /// it for free — and it's protected from rename/delete + immutable so the
    /// name (its identity) and its emptiness both hold. `SeedData.ensureBodyweightKit`
    /// guarantees it exists and re-creates it if removed.
    static let bodyweightName = "null"

    /// The null kit's gear read-out (Dave's line, trimmed to fit a row): an
    /// empty kit that leans into the joke instead of a bare "bodyweight only".
    static let bodyweightCaption = "just you, plus maybe shoes"

    /// The ONE canonical line explaining what a kit is and what switching
    /// does (2026-07-20, Dave's wording). Every surface that captions the
    /// kit switcher references THIS — don't restate it, or the app grows
    /// competing versions. The blank line is deliberate (two beats).
    static let switchingBlurb = "Your selected kit determines which exercises your routines can include.\n\nSwitch kits when you travel, and add to your kit to unlock more exercises."

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

    /// The active kit named for PROSE (card copy, tray blurbs): the kit's
    /// name once more than one kit exists, else the generic possessive.
    /// ONE rule in ONE place so the "count > 1 ? name : your kit" logic can't
    /// drift across call sites. Switcher CONTROLS (the Kit-tab pill, the
    /// catalog "Adding to" strip, the routine Kit chip) deliberately do NOT
    /// use this — a control always shows the raw name, since it needs a label
    /// even with a single kit.
    static func activeNamePhrase(in libraries: [EquipmentLibrary], storedID: String?, generic: String = "your kit") -> String {
        guard let activeKit = active(in: libraries, storedID: storedID) else { return generic }
        // The baked-in null kit is ALWAYS present, so it can't count toward
        // "more than one exists" — a user with a single real kit still reads
        // the generic possessive. But when null itself is the active scope,
        // name it (it's a deliberate named lens, not "your kit").
        let realKits = libraries.filter { !$0.isBodyweight }.count
        guard realKits > 1 || activeKit.isBodyweight else { return generic }
        return activeKit.name
    }

    /// Non-view resolution (SeedData's populate math, the importer).
    static func active(context: ModelContext) -> EquipmentLibrary? {
        let all = (try? context.fetch(FetchDescriptor<EquipmentLibrary>())) ?? []
        return active(in: all)
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

    /// The baked-in no-equipment kit: protected (no rename/delete) and
    /// immutable (membership writes no-op), so it stays a true empty set.
    var isBodyweight: Bool { name == EquipmentLibrary.bodyweightName }

    func setMembership(_ item: Equipment, _ included: Bool) {
        // The null kit is permanently empty — the no-equipment option can't
        // acquire equipment, whatever surface asks.
        guard !isBodyweight else { return }
        if included {
            guard !contains(item) else { return }
            equipment = (equipment ?? []) + [item]
        } else {
            equipment?.removeAll { $0 === item }
        }
    }
}
