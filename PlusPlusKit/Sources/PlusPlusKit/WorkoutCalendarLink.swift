import Foundation

/// Deep links that start a specific routine (#333, calendar sync). A
/// scheduled workout written into the user's calendar carries one of
/// these as its event URL, so tapping the event opens PlusPlus straight
/// into that routine's start.
///
/// Wire forms, both routed by the app to the existing
/// `.plusplusStartRoutine` pathway:
///   - `https://plusplus.fit/start/<name>` (universal link; the
///     not-installed fallback is a static page at the same path)
///   - `plusplus://start/<name>` (custom scheme)
///
/// Identity is the routine NAME (#32) — the same key Siri, the widget
/// snapshot, and the broken-reference session fallback all use. The name
/// is a single percent-encoded path segment, so slashes or spaces in a
/// name ("Push / Pull") survive the round trip.
public enum WorkoutCalendarLink {
    /// The app's custom scheme (shared with `RoutineShareLink`).
    public static let appScheme = "plusplus"
    /// The universal-link host.
    public static let webHost = "plusplus.fit"
    /// The path prefix that marks a start link, in both forms.
    public static let pathPrefix = "start"

    /// Unreserved URL characters (RFC 3986 §2.3): everything else in a
    /// routine name is percent-encoded so the name is exactly one path
    /// segment.
    private static let nameAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    // MARK: - Build

    /// The universal-link form for a routine, or nil for a name that
    /// can't be encoded (empty).
    public static func webURL(forRoutineNamed name: String) -> URL? {
        guard let encoded = encode(name) else { return nil }
        return URL(string: "https://\(webHost)/\(pathPrefix)/\(encoded)")
    }

    /// The custom-scheme form for a routine.
    public static func appURL(forRoutineNamed name: String) -> URL? {
        guard let encoded = encode(name) else { return nil }
        return URL(string: "\(appScheme)://\(pathPrefix)/\(encoded)")
    }

    private static func encode(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: nameAllowed),
              !encoded.isEmpty
        else { return nil }
        return encoded
    }

    // MARK: - Parse

    /// The routine name a start link points at, or nil if the URL isn't
    /// a start link. Accepts both wire forms and tolerates a trailing
    /// slash (the site serves `trailingSlash: true`).
    public static func routineName(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        // Split the ENCODED path so an encoded slash inside a name isn't
        // mistaken for a segment boundary, then decode each piece.
        let pathSegments = components.percentEncodedPath
            .split(separator: "/")
            .map(String.init)

        if url.scheme == appScheme {
            // plusplus://start/<name> parses "start" as the host.
            guard components.host == pathPrefix, let first = pathSegments.first else { return nil }
            return first.removingPercentEncoding
        }
        if components.host == webHost {
            guard pathSegments.count >= 2, pathSegments[0] == pathPrefix else { return nil }
            return pathSegments[1].removingPercentEncoding
        }
        return nil
    }

    /// Whether a URL is shaped like a start link at all, before decoding.
    public static func isStartLink(_ url: URL) -> Bool {
        routineName(from: url) != nil
    }
}
