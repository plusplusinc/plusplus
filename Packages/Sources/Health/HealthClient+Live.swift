import Foundation
import HealthKit
import WorkoutStore

extension HealthClient {
    /// Apple Health on this device, through one store ("You need only a single HealthKit store
    /// per app"), made at the first call rather than at launch. Asks only to write workouts;
    /// reads nothing.
    public static let live = HealthClient(
        access: {
            guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
            return switch store.authorizationStatus(for: .workoutType()) {
            case .sharingAuthorized: .on
            case .sharingDenied: .off
            case .notDetermined: .notAsked
            @unknown default: .off
            }
        },
        ask: {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
        },
        save: { workout in
            try await save(workout, to: store)
        },
    )

    /// A static, so it is made on first use.
    private static let store = HKHealthStore()

    private static func save(_ workout: HealthWorkout, to store: HKHealthStore) async throws {
        let builder = HKWorkoutBuilder(
            healthStore: store,
            configuration: configuration(for: workout),
            device: .local(),
        )
        try await builder.beginCollection(at: workout.start)
        try await builder.addMetadata(metadata(for: workout))
        // Health leaves the time between a pause and its resume out of the workout's length.
        let events = workout.pauses.flatMap { pause in
            [
                HKWorkoutEvent(
                    type: .pause,
                    dateInterval: DateInterval(start: pause.start, duration: 0),
                    metadata: nil,
                ),
                HKWorkoutEvent(
                    type: .resume,
                    dateInterval: DateInterval(start: pause.end, duration: 0),
                    metadata: nil,
                ),
            ]
        }
        if !events.isEmpty {
            try await builder.addWorkoutEvents(events)
        }
        try await builder.endCollection(at: workout.end)
        _ = try await builder.finishWorkout()
    }

    /// The workout's type, done indoors: every workout the app saves is one.
    static func configuration(for workout: HealthWorkout) -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = workout.activity.type
        configuration.locationType = .indoor
        return configuration
    }

    /// Indoors, for Health's "Indoor Workout" row, and the logged workout's own id, by which the
    /// app can find the Health workout it saved for one.
    static func metadata(for workout: HealthWorkout) -> [String: Any] {
        [
            HKMetadataKeyIndoorWorkout: true,
            HKMetadataKeyExternalUUID: workout.id.uuidString,
        ]
    }
}

extension HealthActivity {
    var type: HKWorkoutActivityType {
        switch self {
        case .traditionalStrength: .traditionalStrengthTraining
        case .functionalStrength: .functionalStrengthTraining
        case .highIntensityIntervals: .highIntensityIntervalTraining
        case .flexibility: .flexibility
        }
    }
}
