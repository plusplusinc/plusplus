import Foundation
import HealthKit
import Testing
import WorkoutStore
@testable import Health

/// What the live client hands HealthKit for a workout, read without a Health store.
@Suite("What Apple Health is told")
struct HealthKitTests {
    private let workout = HealthWorkout(
        id: UUID(),
        activity: .traditionalStrength,
        start: Date(timeIntervalSinceReferenceDate: 0),
        end: Date(timeIntervalSinceReferenceDate: 600),
        pauses: [],
    )

    @Test("A workout goes as traditional strength training, done indoors")
    func indoorStrength() {
        let configuration = HealthClient.configuration(for: workout)
        #expect(configuration.activityType == .traditionalStrengthTraining)
        #expect(configuration.locationType == .indoor)
        #expect(HealthClient.metadata(for: workout)[HKMetadataKeyIndoorWorkout] as? Bool == true)
    }

    @Test("A workout carries its logged workout's id, and nothing more")
    func externalID() {
        let metadata = HealthClient.metadata(for: workout)
        #expect(metadata[HKMetadataKeyExternalUUID] as? String == workout.id.uuidString)
        #expect(Set(metadata.keys) == [HKMetadataKeyIndoorWorkout, HKMetadataKeyExternalUUID])
    }
}
