import Foundation
import Testing
import PlusPlusKit

/// Darwin twin of the Kit's `GPXTests.goldenBytes` (which CI runs on Linux
/// only): the sidecar writer's bytes are a sync invariant replayed forever,
/// so the freeze must be pinned on the platform iPhones actually run — a
/// Darwin Foundation change to printf-family formatting would otherwise ship
/// as silent byte drift the Linux suite promised couldn't happen. The
/// expected bytes are DUPLICATED from the Kit test deliberately: changing
/// the frozen format must require touching both pins consciously.
@Suite("GPX writer determinism (Darwin)")
struct GPXDarwinDeterminismTests {
    @Test("The frozen golden bytes reproduce on Darwin")
    func goldenBytes() {
        let iso = ISO8601DateFormatter()
        let track = RouteTrack(segments: [
            [
                .init(latitude: 37.774930, longitude: -122.419416, elevation: 12.3, time: iso.date(from: "2026-07-15T14:01:02Z")!),
                .init(latitude: 37.775100, longitude: -122.419500, elevation: 12.8, time: iso.date(from: "2026-07-15T14:01:12Z")!),
            ],
            [
                .init(latitude: 37.775300, longitude: -122.419600, time: iso.date(from: "2026-07-15T14:03:00Z")!),
                .init(latitude: 37.775500, longitude: -122.419700, time: iso.date(from: "2026-07-15T14:03:10Z")!),
            ],
        ])
        let data = GPX.encode(track, name: "Morning Run", startedAt: iso.date(from: "2026-07-15T14:01:00Z")!)
        let expected = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="PlusPlus" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata><time>2026-07-15T14:01:00Z</time></metadata>
          <trk>
            <name>Morning Run</name>
            <trkseg>
              <trkpt lat="37.774930" lon="-122.419416"><ele>12.3</ele><time>2026-07-15T14:01:02Z</time></trkpt>
              <trkpt lat="37.775100" lon="-122.419500"><ele>12.8</ele><time>2026-07-15T14:01:12Z</time></trkpt>
            </trkseg>
            <trkseg>
              <trkpt lat="37.775300" lon="-122.419600"><time>2026-07-15T14:03:00Z</time></trkpt>
              <trkpt lat="37.775500" lon="-122.419700"><time>2026-07-15T14:03:10Z</time></trkpt>
            </trkseg>
          </trk>
        </gpx>

        """
        #expect(data == Data(expected.utf8))
    }
}
