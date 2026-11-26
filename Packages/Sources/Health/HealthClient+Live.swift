import Foundation
import HealthKit
import WorkoutStore

extension HealthClient {
    /// Apple Health on this device, through one store ("You need only a single HealthKit store
    /// per app"). Asks only to write workouts; reads nothing.
    public static let live: HealthClient = {
        let store = HKHealthStore()
        let workouts: Set<HKSampleType> = [HKObjectType.workoutType()]
        return HealthClient(
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
                try await store.requestAuthorization(toShare: workouts, read: [])
            },
            save: { workout in
                try await save(workout, to: store)
            },
        )
    }()

    private static func save(
        _ workout: HealthWorkout,
        to store: HKHealthStore,
    ) async throws -> UUID {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = workout.activity.type
        let builder = HKWorkoutBuilder(
            healthStore: store,
            configuration: configuration,
            device: .local(),
        )
        try await builder.beginCollection(at: workout.start)
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
        guard let saved = try await builder.finishWorkout() else { throw HealthNotSaved() }
        return saved.uuid
    }
}

/// Health finished the workout but handed none back.
struct HealthNotSaved: Error { }

extension HealthActivity {
    var type: HKWorkoutActivityType {
        switch self {
        case .traditionalStrength: .traditionalStrengthTraining
        }
    }
}
