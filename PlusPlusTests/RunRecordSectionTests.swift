import Foundation
import MapKit
import Testing
import PlusPlusKit
@testable import PlusPlus

/// The record section's pure display math (#378 PR 4). The rendered view
/// needs a device pass (MapKit/Charts aren't exercisable headlessly), but
/// the formatting and fitting logic are plain functions.
@Suite("RunRecordSection display math")
struct RunRecordSectionTests {
    @Test("Pace formats m:ss")
    func paceText() {
        #expect(RunRecordSection.paceText(522) == "8:42")
        #expect(RunRecordSection.paceText(59.6) == "1:00")
        #expect(RunRecordSection.paceText(3601) == "60:01")
    }

    @Test("Split labels name full buckets and honest partials")
    func splitLabels() {
        let full = RouteTrack.Split(index: 3, meters: 1609.344, seconds: 511, paceSeconds: 511)
        #expect(RunRecordSection.splitLabel(full, unit: .miles) == "MI 3")

        let partial = RouteTrack.Split(index: 4, meters: 640, seconds: 205, paceSeconds: 515)
        #expect(RunRecordSection.splitLabel(partial, unit: .miles) == "0.4 MI")

        let erg = RouteTrack.Split(index: 2, meters: 500, seconds: 110, paceSeconds: 110)
        #expect(RunRecordSection.splitLabel(erg, unit: .meters) == "500M 2")

        let ergPartial = RouteTrack.Split(index: 3, meters: 200, seconds: 46, paceSeconds: 115)
        #expect(RunRecordSection.splitLabel(ergPartial, unit: .meters) == "200M")
    }

    @Test("The map region fits the track with padding")
    func regionFitting() {
        let start = Date(timeIntervalSince1970: 1_752_000_000)
        let track = RouteTrack(segments: [[
            .init(latitude: 37.70, longitude: -122.45, time: start),
            .init(latitude: 37.80, longitude: -122.40, time: start.addingTimeInterval(600)),
        ]])
        let region = RunRecordSection.region(fitting: track)
        #expect(abs(region.center.latitude - 37.75) < 0.001)
        #expect(abs(region.center.longitude - (-122.425)) < 0.001)
        #expect(region.span.latitudeDelta > 0.1, "padded beyond the raw bounding box")
        #expect(region.span.longitudeDelta > 0.05)
    }
}
