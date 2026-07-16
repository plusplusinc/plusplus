import Foundation
import Testing
import PlusPlusKit

@Suite("GPX codec")
struct GPXTests {
    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private var sampleTrack: RouteTrack {
        RouteTrack(segments: [
            [
                .init(latitude: 37.774930, longitude: -122.419416, elevation: 12.3, time: date("2026-07-15T14:01:02Z")),
                .init(latitude: 37.775100, longitude: -122.419500, elevation: 12.8, time: date("2026-07-15T14:01:12Z")),
            ],
            [
                .init(latitude: 37.775300, longitude: -122.419600, time: date("2026-07-15T14:03:00Z")),
                .init(latitude: 37.775500, longitude: -122.419700, time: date("2026-07-15T14:03:10Z")),
            ],
        ])
    }

    @Test("The writer's bytes are frozen — the sync layer replays them forever")
    func goldenBytes() {
        let data = GPX.encode(sampleTrack, name: "Morning Run", startedAt: date("2026-07-15T14:01:00Z"))
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

    @Test("decode ∘ encode is an exact fixed point")
    func fixedPoint() throws {
        let bytes = GPX.encode(sampleTrack, name: "Morning Run", startedAt: date("2026-07-15T14:01:00Z"))
        let decoded = try GPX.decode(bytes)
        #expect(decoded.track == sampleTrack)
        #expect(decoded.name == "Morning Run")
        // And re-encoding the decoded track reproduces the bytes.
        let again = GPX.encode(decoded.track, name: decoded.name ?? "", startedAt: date("2026-07-15T14:01:00Z"))
        #expect(again == bytes)
    }

    @Test("Names XML-escape and round-trip")
    func escaping() throws {
        let name = "Y's & T's <Fast>"
        let bytes = GPX.encode(sampleTrack, name: name, startedAt: date("2026-07-15T14:01:00Z"))
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(text.contains("<name>Y's &amp; T's &lt;Fast&gt;</name>"))
        #expect(try GPX.decode(bytes).name == name)
    }

    @Test("A foreign file parses tolerantly")
    func foreignFile() throws {
        let foreign = """
        <?xml version="1.0"?>
        <gpx version="1.1" creator="SomeOtherApp" xmlns="http://www.topografix.com/GPX/1/1" xmlns:gpxtpx="http://example.com/tpx">
          <metadata><name>metadata name, not the track's</name></metadata>
          <wpt lat="1.0" lon="1.0"><time>2026-01-01T00:00:00Z</time></wpt>
          <trk>
            <name>Lunch Run</name>
            <trkseg>
              <trkpt lat="37.1" lon="-122.1"><ele>10.0</ele><time>2026-01-01T10:00:00.000Z</time><extensions><gpxtpx:hr>140</gpxtpx:hr></extensions></trkpt>
              <trkpt lat="37.2" lon="-122.2"><time>2026-01-01T10:00:05Z</time></trkpt>
              <trkpt lat="37.3" lon="-122.3"></trkpt>
            </trkseg>
          </trk>
        </gpx>
        """
        let decoded = try GPX.decode(Data(foreign.utf8))
        #expect(decoded.name == "Lunch Run")
        #expect(decoded.track.segments.count == 1)
        // The timeless third point is dropped; fractional seconds parse.
        #expect(decoded.track.segments[0].count == 2)
        #expect(decoded.track.segments[0][0].elevation == 10.0)
        #expect(decoded.track.segments[0][0].time == date("2026-01-01T10:00:00Z"))
    }

    @Test("A poisoned sidecar (nan/inf values) decodes sanitized, never NaN")
    func nonFiniteInput() throws {
        let poisoned = """
        <gpx version="1.1" creator="X" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><name>Bad Run</name>
            <trkseg>
              <trkpt lat="37.1" lon="-122.1"><time>2026-01-01T10:00:00Z</time></trkpt>
              <trkpt lat="nan" lon="-122.2"><time>2026-01-01T10:00:05Z</time></trkpt>
              <trkpt lat="37.2" lon="-122.2"><ele>inf</ele><time>2026-01-01T10:00:10Z</time></trkpt>
            </trkseg>
          </trk>
        </gpx>
        """
        let decoded = try GPX.decode(Data(poisoned.utf8))
        #expect(decoded.track.segments == [[
            .init(latitude: 37.1, longitude: -122.1, time: date("2026-01-01T10:00:00Z")),
            .init(latitude: 37.2, longitude: -122.2, elevation: nil, time: date("2026-01-01T10:00:10Z")),
        ]])
        #expect(decoded.track.totalMeters.isFinite)
    }

    @Test("A route (rte/rtept) reads as one segment")
    func routePoints() throws {
        let rte = """
        <gpx version="1.1" creator="X" xmlns="http://www.topografix.com/GPX/1/1">
          <rte>
            <rtept lat="37.1" lon="-122.1"><time>2026-01-01T10:00:00Z</time></rtept>
            <rtept lat="37.2" lon="-122.2"><time>2026-01-01T10:00:05Z</time></rtept>
          </rte>
        </gpx>
        """
        let decoded = try GPX.decode(Data(rte.utf8))
        #expect(decoded.track.segments.count == 1)
        #expect(decoded.track.segments[0].count == 2)
    }

    @Test("Non-GPX bytes throw")
    func notGPX() {
        #expect(throws: GPX.DecodeError.notAGPXDocument) {
            _ = try GPX.decode(Data("not xml at all".utf8))
        }
        #expect(throws: GPX.DecodeError.notAGPXDocument) {
            _ = try GPX.decode(Data("<foo><bar/></foo>".utf8))
        }
    }

    @Test("Sidecar paths pair by basename")
    func sidecarPath() {
        #expect(
            FileLayout.routeSidecarPath(forSessionPath: "history/2026/2026-07-15-morning-run.json")
                == "history/2026/2026-07-15-morning-run.gpx"
        )
        #expect(
            FileLayout.routeSidecarPath(forSessionPath: "history/2026/2026-07-15-morning-run-2.json")
                == "history/2026/2026-07-15-morning-run-2.gpx"
        )
    }
}
