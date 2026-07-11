import Foundation

/// Field-level three-way merge for a template file that changed on BOTH sides
/// since the last sync. Where whole-file merging would declare a conflict, this
/// merges the DTO's fields independently: a field changed on only one side
/// takes that side, so editing `restSeconds` on the phone and `notes` in the
/// repo both apply cleanly — no conflict at all. Only a field changed on both
/// sides to different values is a genuine collision, and that resolves
/// **local-wins** (the app's SwiftData store is the live source of truth,
/// docs/PLATFORM.md; and git history preserves the overwritten value, so
/// nothing is truly lost). This is the same last-writer philosophy the live
/// phone/watch mirror uses (#322).
///
/// Sessions never reach here (append-only, no conflicts). Returns nil when the
/// path isn't a known template shape or the inputs don't decode — the caller
/// then falls back to explicit conflict resolution.
public enum TemplateMerge {
    /// The document wrapper key whose inner object carries the mergeable
    /// fields, per template kind. Merging happens INSIDE this key so a routine's
    /// `name`/`restSeconds`/`notes`/`groups` merge independently, not the whole
    /// `routine` object as one blob.
    private static func innerKey(for path: String) -> String? {
        if path.hasPrefix(FileLayout.routinesDirectory + "/") { return "routine" }
        if path.hasPrefix(FileLayout.exercisesDirectory + "/") { return "exercise" }
        if path.hasPrefix(FileLayout.equipmentLibrariesDirectory + "/") { return "library" }
        if path.hasPrefix(FileLayout.equipmentDirectory + "/") { return "equipment" }
        return nil
    }

    public static func merge(base: Data?, local: Data, remote: Data, path: String) -> Data? {
        guard let key = innerKey(for: path),
              let localDoc = object(local), let remoteDoc = object(remote),
              let localInner = localDoc[key] as? [String: Any],
              let remoteInner = remoteDoc[key] as? [String: Any]
        else { return nil }
        let baseInner = (base.flatMap(object)?[key] as? [String: Any]) ?? [:]

        // Merge the inner DTO's fields, then re-wrap in the local document
        // envelope (schemaVersion etc. agree across sides).
        var mergedDoc = localDoc
        mergedDoc[key] = mergedFields(local: localInner, remote: remoteInner, base: baseInner)

        guard let raw = try? JSONSerialization.data(withJSONObject: mergedDoc) else { return nil }
        // Canonicalize through the codec so the bytes match what the app
        // writes (sorted keys, ISO dates) — otherwise the next sync sees a
        // spurious diff. Decoding also validates the merge produced a legal DTO.
        return try? canonicalize(raw, path: path)
    }

    private static func mergedFields(
        local: [String: Any], remote: [String: Any], base: [String: Any]
    ) -> [String: Any] {
        var merged: [String: Any] = [:]
        for field in Set(local.keys).union(remote.keys) {
            let l = local[field], r = remote[field], b = base[field]
            let winner: Any?
            if jsonEqual(l, r) {
                winner = l                       // agree (covers both-absent)
            } else if jsonEqual(r, b) {
                winner = l                       // remote unchanged → local (incl. local-added/removed)
            } else if jsonEqual(l, b) {
                winner = r                       // local unchanged → remote
            } else {
                winner = l                       // both changed → local wins
            }
            if let winner { merged[field] = winner }   // nil = the winning side dropped the field
        }
        return merged
    }

    // MARK: - Helpers

    private static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func jsonEqual(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return (x as? NSObject)?.isEqual(y) ?? false
        default: return false
        }
    }

    private static func canonicalize(_ data: Data, path: String) throws -> Data {
        if path.hasPrefix(FileLayout.routinesDirectory + "/") {
            return try InterchangeCodec.encode(InterchangeCodec.decode(RoutineDocument.self, from: data))
        }
        if path.hasPrefix(FileLayout.exercisesDirectory + "/") {
            return try InterchangeCodec.encode(InterchangeCodec.decode(ExerciseDocument.self, from: data))
        }
        if path.hasPrefix(FileLayout.equipmentLibrariesDirectory + "/") {
            return try InterchangeCodec.encode(InterchangeCodec.decode(EquipmentLibraryDocument.self, from: data))
        }
        if path.hasPrefix(FileLayout.equipmentDirectory + "/") {
            return try InterchangeCodec.encode(InterchangeCodec.decode(EquipmentDocument.self, from: data))
        }
        throw CanonicalizeError.notTemplate
    }

    private enum CanonicalizeError: Error { case notTemplate }
}
