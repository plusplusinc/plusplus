import Foundation
import SwiftData
import PlusPlusKit

/// Attaches pulled GPX route sidecars (#378) to their sessions. The pull
/// path's bundle assembly skips non-JSON files by design (`InterchangeFiles`),
/// so sidecars arrive here, AFTER `importBundle` has materialized any new
/// sessions from the same pull set. The JSON summary stays authoritative —
/// an attached sidecar never recomputes `runDistanceMeters` and friends; it
/// only supplies the map/splits bytes the record screen parses on demand.
enum RouteSidecars {
    /// Pair each pulled `.gpx` with its session and attach the bytes
    /// verbatim (they must replay byte-for-byte in the local file map).
    /// Two ways to pair, in order:
    /// 1. The JSON twin (same basename) in the SAME pull set — the restore
    ///    case, exact identity from the decoded document.
    /// 2. The filename convention (`YYYY-MM-DD-slug[-N].gpx`) against
    ///    existing sessions — the "another device pushed a run" case.
    /// Attach only onto a session that has no route yet; anything
    /// unresolvable is skipped silently (the sidecar stays in the repo and
    /// in the base — nothing is lost, and a later pass can try again).
    static func attach(pulls: [FileWrite], context: ModelContext) {
        let sidecars = pulls.filter {
            $0.path.hasPrefix(FileLayout.historyDirectory + "/") && $0.path.hasSuffix(".gpx")
        }
        guard !sidecars.isEmpty,
              let sessions = try? context.fetch(FetchDescriptor<WorkoutSession>()) else { return }

        let jsonByPath = Dictionary(
            uniqueKeysWithValues: pulls.filter { $0.path.hasSuffix(".json") }.map { ($0.path, $0.data) }
        )

        for sidecar in sidecars {
            let twinPath = String(sidecar.path.dropLast(".gpx".count)) + ".json"
            if let twinData = jsonByPath[twinPath],
               let document = try? InterchangeCodec.decode(SessionDocument.self, from: twinData) {
                let dto = document.session
                let match = sessions.first {
                    $0.endedAt != nil
                        && $0.routineName.compare(dto.routineName, options: .caseInsensitive) == .orderedSame
                        && abs($0.startedAt.timeIntervalSince(dto.startedAt)) < 1
                }
                if let match, match.routeData == nil {
                    match.routeData = sidecar.data
                }
                continue
            }

            // Orphan sidecar (its JSON was already local): pair by the
            // naming convention. Only an UNAMBIGUOUS match may attach — a
            // wrong route on the wrong record is worse than no map.
            guard let key = parse(path: sidecar.path) else { continue }
            let slugs = slugCandidates(key.slug)
            // Finished sessions only: an in-progress same-day run must
            // never grab a sidecar (its own finish will write the truth).
            let candidates = sessions.filter { session in
                session.routeData == nil
                    && session.endedAt != nil
                    && FileLayout.utcDateParts(of: session.startedAt).dateStamp == key.stamp
                    && slugs.contains(Slug.make(session.routineName))
            }
            if candidates.count == 1 {
                candidates[0].routeData = sidecar.data
            }
        }
    }

    /// "history/2026/2026-07-15-morning-run-2.gpx" → ("2026-07-15",
    /// "morning-run"). A trailing `-N` is the same-day numbered suffix from
    /// `sessionPlacement`; it's stripped for the slug match (a slug that
    /// genuinely ends in digits still matches via the un-stripped try).
    private static func parse(path: String) -> (stamp: String, slug: String)? {
        guard let file = path.split(separator: "/").last, file.hasSuffix(".gpx") else { return nil }
        let base = String(file.dropLast(".gpx".count))
        // The stamp is the first 10 characters (YYYY-MM-DD) + a hyphen.
        guard base.count > 11 else { return nil }
        let stamp = String(base.prefix(10))
        let slug = String(base.dropFirst(11))
        return (stamp, slug)
    }
}

extension RouteSidecars {
    /// The parsed slug plus its numbered-suffix-stripped form: a `-2`
    /// same-day placement suffix belongs to the FILENAME, not the routine —
    /// but a routine slug genuinely ending in digits still matches via the
    /// un-stripped entry. Ambiguity (both forms matching different
    /// sessions) falls out as candidates.count > 1 → skip.
    static func slugCandidates(_ slug: String) -> [String] {
        var candidates = [slug]
        if let range = slug.range(of: #"-\d+$"#, options: .regularExpression) {
            candidates.append(String(slug[..<range.lowerBound]))
        }
        return candidates
    }
}
