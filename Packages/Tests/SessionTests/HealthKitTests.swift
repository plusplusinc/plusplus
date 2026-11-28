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

    @Test("Each of the app's types goes as Health's own, done indoors", arguments: [
        (HealthActivity.traditionalStrength, HKWorkoutActivityType.traditionalStrengthTraining),
        (.functionalStrength, .functionalStrengthTraining),
        (.highIntensityIntervals, .highIntensityIntervalTraining),
        (.flexibility, .flexibility),
    ])
    func indoorType(activity: HealthActivity, type: HKWorkoutActivityType) {
        let typed = HealthWorkout(
            id: workout.id,
            activity: activity,
            start: workout.start,
            end: workout.end,
            pauses: [],
        )
        let configuration = HealthClient.configuration(for: typed)
        #expect(configuration.activityType == type)
        #expect(configuration.locationType == .indoor)
        #expect(HealthClient.metadata(for: typed)[HKMetadataKeyIndoorWorkout] as? Bool == true)
    }

    @Test("A workout carries its workout session's id, and nothing more")
    func externalID() {
        let metadata = HealthClient.metadata(for: workout)
        #expect(metadata[HKMetadataKeyExternalUUID] as? String == workout.id.uuidString)
        #expect(Set(metadata.keys) == [HKMetadataKeyIndoorWorkout, HKMetadataKeyExternalUUID])
    }
}
