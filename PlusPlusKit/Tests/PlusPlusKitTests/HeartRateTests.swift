import Foundation
import Testing
@testable import PlusPlusKit

@Suite("HeartRate")
struct HeartRateTests {
    // MARK: - Max HR estimate

    @Test func estimatedMaxSubtractsAge() {
        #expect(HeartRate.estimatedMax(age: 30) == 190)
        #expect(HeartRate.estimatedMax(age: 55) == 165)
    }

    @Test func estimatedMaxClampsNonsense() {
        // A typo'd birthday (age 0 or 150) must not produce zones
        // nobody has.
        #expect(HeartRate.estimatedMax(age: 0) == 220)
        #expect(HeartRate.estimatedMax(age: 150) == 120)
        #expect(HeartRate.estimatedMax(age: -5) == 220)
    }

    // MARK: - Zones

    @Test func zoneBoundsAtMax190() {
        // The canonical five-zone split of 190: adjacent zones must not
        // overlap and must tile the 50–100% band.
        #expect(HeartRateZone.zone1.bpmRange(maxHeartRate: 190) == 95...113)
        #expect(HeartRateZone.zone2.bpmRange(maxHeartRate: 190) == 114...132)
        #expect(HeartRateZone.zone3.bpmRange(maxHeartRate: 190) == 133...151)
        #expect(HeartRateZone.zone4.bpmRange(maxHeartRate: 190) == 152...170)
        #expect(HeartRateZone.zone5.bpmRange(maxHeartRate: 190) == 171...190)
    }

    @Test func zoneLookupMatchesBounds() {
        // Every zone's own display bounds must classify back to it.
        for zone in HeartRateZone.allCases {
            let range = zone.bpmRange(maxHeartRate: 190)
            #expect(HeartRateZone.zone(for: range.lowerBound, maxHeartRate: 190) == zone)
            #expect(HeartRateZone.zone(for: range.upperBound, maxHeartRate: 190) == zone)
        }
    }

    @Test func zoneLookupEdges() {
        // Below 50% is rest, not a zone; beyond max is still zone 5.
        #expect(HeartRateZone.zone(for: 80, maxHeartRate: 190) == nil)
        #expect(HeartRateZone.zone(for: 205, maxHeartRate: 190) == .zone5)
        #expect(HeartRateZone.zone(for: 100, maxHeartRate: 0) == nil)
    }

    // MARK: - Targets

    @Test func zoneTargetContainment() {
        let target = HeartRateTarget.zone(.zone2)
        #expect(target.contains(120, maxHeartRate: 190))
        #expect(!target.contains(140, maxHeartRate: 190))
        #expect(!target.contains(100, maxHeartRate: 190))
    }

    @Test func zoneFiveIsOpenAbove() {
        let target = HeartRateTarget.zone(.zone5)
        #expect(target.contains(200, maxHeartRate: 190), "beyond max is not a miss")
        #expect(!target.contains(160, maxHeartRate: 190))
    }

    @Test func rangeTargetNormalizesSwappedBounds() {
        let target = HeartRateTarget.range(lowerBPM: 150, upperBPM: 130)
        #expect(target.bpmRange(maxHeartRate: 190) == 130...150)
        #expect(target.contains(140, maxHeartRate: 190))
        #expect(target.label(maxHeartRate: 190) == "130–150 bpm")
    }

    @Test func labels() {
        #expect(HeartRateTarget.zone(.zone2).label(maxHeartRate: 190) == "Z2 · 114–132")
        #expect(HeartRateTarget.zone(.zone2).label(maxHeartRate: nil) == "Zone 2")
        #expect(HeartRateTarget.range(lowerBPM: 130, upperBPM: 150).label(maxHeartRate: nil) == "130–150 bpm")
    }

    // MARK: - Codec

    @Test func targetEncodingIsExplicit() throws {
        // Persisted shape (SwiftData blobs, watch payloads): named keys,
        // never the compiler's synthesized associated-value layout.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let zoneJSON = String(data: try encoder.encode(HeartRateTarget.zone(.zone3)), encoding: .utf8)
        #expect(zoneJSON == #"{"kind":"zone","zone":3}"#)
        let rangeJSON = String(data: try encoder.encode(HeartRateTarget.range(lowerBPM: 130, upperBPM: 150)), encoding: .utf8)
        #expect(rangeJSON == #"{"kind":"range","lower":130,"upper":150}"#)
    }

    @Test func targetRoundTrips() throws {
        for target: HeartRateTarget in [.zone(.zone1), .zone(.zone5), .range(lowerBPM: 110, upperBPM: 125)] {
            let data = try JSONEncoder().encode(target)
            #expect(try JSONDecoder().decode(HeartRateTarget.self, from: data) == target)
        }
    }

    @Test func unknownZoneFailsLoudly() {
        let data = Data(#"{"kind":"zone","zone":9}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(HeartRateTarget.self, from: data)
        }
    }
}
