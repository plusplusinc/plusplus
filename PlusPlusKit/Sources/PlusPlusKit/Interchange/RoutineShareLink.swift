import Foundation

/// Share-a-routine links (#145, PLG #141-A): one routine plus the
/// exercise definitions it references, encoded INTO the URL itself.
/// The payload rides the fragment, so it is never sent to any server —
/// the plusplus.fit viewer decodes it entirely in the browser, and the
/// app imports it through the normal interchange pipeline.
///
/// Wire format: `https://plusplus.fit/r#0<base64url(JSON)>`. The
/// leading "0" is an encoding tag (0 = plain JSON; reserved room for a
/// compressed variant later without breaking old viewers). JSON keys
/// are sorted so identical routines produce identical links.
public enum RoutineShareLink {
    public struct Payload: Codable, Equatable, Sendable {
        /// Payload format version — independent of the interchange
        /// schema version, which the DTO shapes carry implicitly.
        public var share: Int
        /// What weight numbers are denominated in; absent = lb, same
        /// convention as ExportBundle.
        public var units: WeightUnit?
        public var routine: RoutineDTO
        /// Definitions for the exercises the routine references, so the
        /// receiver can create anything they don't already have.
        public var exercises: [ExerciseDTO]

        public init(routine: RoutineDTO, exercises: [ExerciseDTO], units: WeightUnit? = nil) {
            self.share = Self.currentVersion
            self.units = units
            self.routine = routine
            self.exercises = exercises.sorted { $0.name.lowercased() < $1.name.lowercased() }
        }

        public static let currentVersion = 1
    }

    /// Where shared links point; the static viewer lives at this path.
    public static let viewerBase = "https://plusplus.fit/r"
    /// The app's custom scheme; `plusplus://r#<fragment>` imports directly.
    public static let appScheme = "plusplus"

    public enum DecodeError: Error, Equatable {
        case missingFragment
        /// Unknown encoding tag — a link made by a newer app.
        case unsupportedEncoding
        case undecodable
        case unsupportedVersion(Int)
    }

    // MARK: - Encode

    public static func fragment(for payload: Payload) throws -> String {
        let encoder = JSONEncoder()
        // Sorted for determinism, compact for URL length; ISO dates to
        // match the interchange codec (none appear today, but the
        // payload should never diverge from the format's conventions).
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return "0" + base64URL(data)
    }

    /// The shareable https URL (renders in any browser, imports via the
    /// viewer's Open-in-PlusPlus button).
    public static func url(for payload: Payload) throws -> URL {
        guard let url = URL(string: viewerBase + "#" + (try fragment(for: payload))) else {
            throw DecodeError.undecodable
        }
        return url
    }

    // MARK: - Decode

    public static func payload(fromFragment fragment: String) throws -> Payload {
        guard !fragment.isEmpty else { throw DecodeError.missingFragment }
        guard fragment.hasPrefix("0") else { throw DecodeError.unsupportedEncoding }
        guard let data = base64URLDecode(String(fragment.dropFirst())) else {
            throw DecodeError.undecodable
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: data) else {
            throw DecodeError.undecodable
        }
        guard payload.share == Payload.currentVersion else {
            throw DecodeError.unsupportedVersion(payload.share)
        }
        return payload
    }

    /// Accepts both link forms — the https viewer URL and the app
    /// scheme (`plusplus://r#…`).
    public static func payload(from url: URL) throws -> Payload {
        guard let fragment = url.fragment else { throw DecodeError.missingFragment }
        return try payload(fromFragment: fragment)
    }

    /// Whether a URL handed to the app looks like a share link at all
    /// (scheme + host/path shaped right), before any decoding.
    public static func isShareLink(_ url: URL) -> Bool {
        if url.scheme == appScheme {
            // plusplus://r#… parses "r" as the host.
            return url.host == "r" || url.path == "/r" || url.path == "r"
        }
        return url.absoluteString.hasPrefix(viewerBase)
    }

    // MARK: - base64url

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecode(_ string: String) -> Data? {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        return Data(base64Encoded: s)
    }
}
