import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// The route sidecar format (#378): a session's GPS track is stored in the
/// repo as `history/YYYY/<same-basename>.gpx` beside its session JSON —
/// GPX 1.1 because every running tool on earth reads it, which is the whole
/// hackable-data point. The writer is DETERMINISTIC and FROZEN: hand-emitted
/// strings (not an XML library — byte identity across macOS/iOS/Linux
/// Foundation is a sync invariant), fixed attribute order and indentation,
/// `%.6f` coordinates, `%.1f` elevation, whole-second UTC times. Changing
/// any of it re-commits every synced sidecar; `GPXTests` pins the exact
/// bytes. The reader is TOLERANT: it accepts foreign files (extensions,
/// namespaces, fractional-second times, missing elevation) so a track
/// exported from another app survives a restore untouched.
public enum GPX {
    public static let creator = "PlusPlus"

    public enum DecodeError: Error, Equatable {
        /// The bytes aren't a parseable GPX document.
        case notAGPXDocument
    }

    // MARK: - Encode

    /// Frozen GPX 1.1 bytes for a track. `name` is the routine name (the
    /// `<trk><name>`), `startedAt` the session start (the `<metadata><time>`).
    public static func encode(_ track: RouteTrack, name: String, startedAt: Date) -> Data {
        var lines: [String] = []
        lines.append(#"<?xml version="1.0" encoding="UTF-8"?>"#)
        lines.append(#"<gpx version="1.1" creator="\#(creator)" xmlns="http://www.topografix.com/GPX/1/1">"#)
        lines.append("  <metadata><time>\(timestamp(startedAt))</time></metadata>")
        lines.append("  <trk>")
        lines.append("    <name>\(escape(name))</name>")
        for segment in track.segments {
            lines.append("    <trkseg>")
            for fix in segment {
                let coordinates = String(format: "lat=\"%.6f\" lon=\"%.6f\"", fix.latitude, fix.longitude)
                let elevation = fix.elevation.map { String(format: "<ele>%.1f</ele>", $0) } ?? ""
                lines.append("      <trkpt \(coordinates)>\(elevation)<time>\(timestamp(fix.time))</time></trkpt>")
            }
            lines.append("    </trkseg>")
        }
        lines.append("  </trk>")
        lines.append("</gpx>")
        lines.append("")
        return Data(lines.joined(separator: "\n").utf8)
    }

    // MARK: - Decode

    /// Parses GPX bytes into a track (and the first `<trk><name>`, when
    /// present). Accepts `trkpt` and `rtept`; one `trkseg` (or one whole
    /// `rte`) becomes one segment; points without a `time` are dropped —
    /// every derivation needs timestamps. `RouteTrack.init` then applies
    /// its usual sanitation, so decode∘encode is an exact fixed point on
    /// tracks this codec wrote.
    public static func decode(_ data: Data) throws -> (track: RouteTrack, name: String?) {
        let collector = Collector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        guard parser.parse(), collector.sawGPXRoot else {
            throw DecodeError.notAGPXDocument
        }
        return (RouteTrack(segments: collector.segments), collector.trackName)
    }

    // MARK: - Internals

    /// Whole-second UTC timestamp, hand-formatted from calendar components —
    /// no formatter classes, no platform variance.
    static func timestamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let p = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02dZ",
            p.year ?? 0, p.month ?? 0, p.day ?? 0, p.hour ?? 0, p.minute ?? 0, p.second ?? 0
        )
    }

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func parseTimestamp(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }

    private final class Collector: NSObject, XMLParserDelegate {
        var sawGPXRoot = false
        var trackName: String?
        var segments: [[RouteTrack.Fix]] = []

        private var currentSegment: [RouteTrack.Fix] = []
        private var path: [String] = []
        private var pointLatitude: Double?
        private var pointLongitude: Double?
        private var pointElevation: Double?
        private var pointTime: Date?
        private var text = ""

        /// Element names compared by local part so a prefixed foreign file
        /// (`<gpx:trkpt>`) still reads.
        private func local(_ elementName: String) -> String {
            elementName.split(separator: ":").last.map(String.init) ?? elementName
        }

        func parser(
            _ parser: XMLParser, didStartElement elementName: String,
            namespaceURI: String?, qualifiedName: String?, attributes: [String: String]
        ) {
            let element = local(elementName)
            path.append(element)
            text = ""
            switch element {
            case "gpx":
                sawGPXRoot = true
            case "trkpt", "rtept":
                pointLatitude = attributes["lat"].flatMap(Double.init)
                pointLongitude = attributes["lon"].flatMap(Double.init)
                pointElevation = nil
                pointTime = nil
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(
            _ parser: XMLParser, didEndElement elementName: String,
            namespaceURI: String?, qualifiedName: String?
        ) {
            let element = local(elementName)
            let inPoint = path.dropLast().last.map { $0 == "trkpt" || $0 == "rtept" } ?? false
            switch element {
            case "ele" where inPoint:
                pointElevation = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
            case "time" where inPoint:
                pointTime = GPX.parseTimestamp(text.trimmingCharacters(in: .whitespacesAndNewlines))
            case "name" where path.suffix(3).elementsEqual(["gpx", "trk", "name"]):
                if trackName == nil {
                    trackName = text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            case "trkpt", "rtept":
                if let lat = pointLatitude, let lon = pointLongitude, let time = pointTime {
                    currentSegment.append(RouteTrack.Fix(
                        latitude: lat, longitude: lon, elevation: pointElevation, time: time
                    ))
                }
            case "trkseg", "rte":
                segments.append(currentSegment)
                currentSegment = []
            default:
                break
            }
            path.removeLast()
        }
    }
}
