import Foundation
import SwiftData
import PlusPlusKit

/// Attaches pulled GPX route sidecars (#378) to their sessions. The pull
/// path's bundle assembly skips non-JSON files by design (`InterchangeFiles`),
/// so sidecars arrive here, AFTER `importBundle` has materialized any new
/// sessions from the same pull set. The JSON summary stays authoritative —
/// an attached sidecar never recomputes `runDistanceMeters` and friends; it
/// only supplies the map/splits bytes the record screen parses on demand.
///
/// **Pulled bytes win.** The planner only hands us a sidecar pull when the
/// remote changed relative to the base (or on restore) — a deliberate
/// repo-side edit, which the hackable ethos invites. Refusing to adopt it
/// would make the next pass read the stale local bytes as an "edit" and
/// push them back over the user's commit (swift-reviewer catch).
enum RouteSidecars {
    /// Pair each pulled `.gpx` with its session and adopt the bytes
    /// verbatim (they must replay byte-for-byte in the local file map).
    /// Pairing, in order:
    /// 1. The JSON twin (same basename) in the SAME pull set — the restore
    ///    case, exact identity from the decoded document.
    /// 2. The filename convention: `YYYY-MM-DD-slug[-N].gpx` names the Nth
    ///    same-day session of that routine in start order — the SAME rule
    ///    `sessionPlacement` used to mint the name (the bundle sorts
    ///    sessions by `startedAt`, so suffix order IS start order on every
    ///    device). No guessing: the ordinal either resolves or it doesn't.
    /// Finished sessions only (an in-progress run's finish writes its own
    /// truth). Returns the sidecars it could NOT place — the caller banks
    /// them (`OrphanSidecarStore`) so the file map still holds their bytes
    /// and a later pass can retry the pairing.
    @discardableResult
    static func attach(pulls: [FileWrite], context: ModelContext) -> [FileWrite] {
        let sidecars = pulls.filter {
            $0.path.hasPrefix(FileLayout.historyDirectory + "/") && $0.path.hasSuffix(".gpx")
        }
        guard !sidecars.isEmpty else { return [] }
        guard let sessions = try? context.fetch(FetchDescriptor<WorkoutSession>()) else { return sidecars }
        let finished = sessions.filter { $0.endedAt != nil }

        let jsonByPath = Dictionary(
            pulls.filter { $0.path.hasSuffix(".json") }.map { ($0.path, $0.data) },
            uniquingKeysWith: { first, _ in first }
        )

        var unplaced: [FileWrite] = []
        for sidecar in sidecars {
            if let session = pair(sidecar, jsonByPath: jsonByPath, finished: finished) {
                if session.routeData != sidecar.data {
                    session.routeData = sidecar.data
                }
            } else {
                unplaced.append(sidecar)
            }
        }
        return unplaced
    }

    private static func pair(
        _ sidecar: FileWrite, jsonByPath: [String: Data], finished: [WorkoutSession]
    ) -> WorkoutSession? {
        // 1. Twin document in the same pull set: exact identity. The <1 s
        // window covers ISO-8601 whole-second truncation of a fractional
        // local start.
        let twinPath = String(sidecar.path.dropLast(".gpx".count)) + ".json"
        if let twinData = jsonByPath[twinPath],
           let document = try? InterchangeCodec.decode(SessionDocument.self, from: twinData) {
            let dto = document.session
            return finished.first {
                $0.routineName.compare(dto.routineName, options: .caseInsensitive) == .orderedSame
                    && abs($0.startedAt.timeIntervalSince(dto.startedAt)) < 1
            }
        }

        // 2. Filename convention. A slug genuinely ending in "-2" is
        // indistinguishable from a placement suffix in the name alone, so
        // interpretations are tried in a fixed order: the whole remainder
        // as slug (ordinal 1) first, then the stripped slug with the
        // parsed ordinal.
        guard let key = parse(path: sidecar.path) else { return nil }
        for candidate in interpretations(of: key.slug) {
            let group = finished
                .filter {
                    FileLayout.utcDateParts(of: $0.startedAt).dateStamp == key.stamp
                        && Slug.make($0.routineName) == candidate.slug
                }
                .sorted { $0.startedAt < $1.startedAt }
            if group.indices.contains(candidate.ordinal - 1) {
                return group[candidate.ordinal - 1]
            }
        }
        return nil
    }

    /// "history/2026/2026-07-15-morning-run-2.gpx" → ("2026-07-15",
    /// "morning-run-2"); ordinal resolution happens in `interpretations`.
    static func parse(path: String) -> (stamp: String, slug: String)? {
        guard let file = path.split(separator: "/").last, file.hasSuffix(".gpx") else { return nil }
        let base = String(file.dropLast(".gpx".count))
        guard base.count > 11 else { return nil }
        return (String(base.prefix(10)), String(base.dropFirst(11)))
    }

    /// The pairing interpretations of a filename remainder, in trial order.
    static func interpretations(of slug: String) -> [(slug: String, ordinal: Int)] {
        var candidates: [(slug: String, ordinal: Int)] = [(slug, 1)]
        if let range = slug.range(of: #"-\d+$"#, options: .regularExpression),
           let ordinal = Int(slug[range].dropFirst()), ordinal >= 2 {
            candidates.append((String(slug[..<range.lowerBound]), ordinal))
        }
        return candidates
    }
}
