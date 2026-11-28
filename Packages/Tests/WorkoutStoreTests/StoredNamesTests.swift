import SwiftData
import Testing
@testable import WorkoutStore

/// SwiftData finds a phone's rows by the entity and property names they were stored under, so a
/// shipped version's names never change. The upgrade tests write each old shape with the same
/// in-code classes they open it with, so a name changed in every version at once passes them;
/// only a literal written down from the code as shipped catches it. V15 to V17 renamed the
/// models, by moving their rows, which is why a name can stop being stored. Nothing else in
/// this file names a type a rename of the code's types could touch, so one has no reason to
/// edit it. It can't see a shape changed under the same names: the committed V14 store can.
@Suite("Stored names")
struct StoredNamesTests {
    private static let shipped: [Int: any VersionedSchema.Type] = [
        1: RoutineSchemaV1.self,
        2: RoutineSchemaV2.self,
        3: RoutineSchemaV3.self,
        4: RoutineSchemaV4.self,
        5: RoutineSchemaV5.self,
        6: RoutineSchemaV6.self,
        7: RoutineSchemaV7.self,
        8: RoutineSchemaV8.self,
        9: RoutineSchemaV9.self,
        10: RoutineSchemaV10.self,
        11: RoutineSchemaV11.self,
        12: RoutineSchemaV12.self,
        13: RoutineSchemaV13.self,
        14: RoutineSchemaV14.self,
        15: StoreSchemaV15.self,
        16: StoreSchemaV16.self,
        17: StoreSchemaV17.self,
    ]

    /// Every stored entity's properties and the version each first shipped in, written down from
    /// the code at a8510b7 for versions 1 to 14, and from the rename's for 15 on. A version
    /// stores the properties that shipped in it or before, less those `lastShipped` has gone.
    private static let firstShipped: [String: [String: Int]] = [
        "StoredCustomization": [
            "changed": 10,
            "editedAt": 10,
            "equipment": 10,
            "exerciseID": 10,
            "isPerSide": 10,
            "measure": 10,
            "muscleGroups": 10,
            "name": 10,
        ],
        "StoredExercise": [
            "createdAt": 8,
            "equipment": 8,
            "id": 8,
            "isPerSide": 8,
            "measure": 8,
            "muscleGroup": 8,
            "muscleGroups": 15,
            "name": 8,
        ],
        "StoredLoggedSet": [
            "clockWhenLogged": 15,
            "exerciseID": 15,
            "exerciseName": 15,
            "id": 15,
            "loggedAt": 15,
            "plannedReps": 15,
            "plannedSeconds": 15,
            "plannedWeight": 15,
            "plannedWeightUnit": 15,
            "position": 15,
            "reps": 15,
            "restAdjustment": 15,
            "restSkippedAt": 15,
            "round": 15,
            "rowID": 15,
            "seconds": 15,
            "side": 15,
            "timeAdded": 15,
            "weight": 15,
            "weightUnit": 15,
            "workoutSession": 15,
        ],
        "StoredRoutine": [
            "editedAt": 1,
            "exercises": 1,
            "id": 1,
            "name": 1,
            "openedAt": 4,
        ],
        "StoredRoutineExercise": [
            "exerciseID": 1,
            "id": 1,
            "isRestAuto": 7,
            "isRoundRestAuto": 7,
            "position": 1,
            "reps": 2,
            "rest": 7,
            "roundRest": 7,
            "routine": 1,
            "seconds": 2,
            "sets": 2,
            "supersetID": 3,
            "weight": 2,
            "weightUnit": 2,
        ],
        "StoredSet": [
            "clockWhenLogged": 11,
            "exerciseID": 6,
            "exerciseName": 9,
            "id": 6,
            "loggedAt": 6,
            "plannedReps": 6,
            "plannedSeconds": 6,
            "plannedWeight": 6,
            "plannedWeightUnit": 6,
            "position": 6,
            "reps": 6,
            "restAdjustment": 11,
            "restSkippedAt": 13,
            "round": 6,
            "rowID": 6,
            "seconds": 6,
            "side": 6,
            "timeAdded": 12,
            "weight": 6,
            "weightUnit": 6,
            "workout": 6,
        ],
        // A session up to 15, and from 16 the workout: `id` is in both.
        "StoredWorkout": [
            "countAdded": 12,
            "countRound": 12,
            "countRowID": 12,
            "countSide": 12,
            "countStartClock": 12,
            "editedAt": 16,
            "endedAt": 5,
            "exercises": 16,
            "healthActivity": 14,
            "healthWorkoutID": 14,
            "id": 5,
            "name": 16,
            "openedAt": 16,
            "pauseTimes": 14,
            "pausedAt": 5,
            "pausedSeconds": 5,
            "routineID": 5,
            "routineName": 5,
            "sets": 6,
            "startedAt": 5,
        ],
        "StoredWorkoutExercise": [
            "exerciseID": 16,
            "id": 16,
            "isRestAuto": 16,
            "isRoundRestAuto": 16,
            "position": 16,
            "reps": 16,
            "rest": 16,
            "roundRest": 16,
            "seconds": 16,
            "sets": 16,
            "supersetID": 16,
            "weight": 16,
            "weightUnit": 16,
            "workout": 16,
        ],
        "StoredWorkoutSession": [
            "countAdded": 15,
            "countRound": 15,
            "countRowID": 15,
            "countSide": 15,
            "countStartClock": 15,
            "endedAt": 15,
            "healthActivity": 15,
            "healthWorkoutID": 15,
            "id": 15,
            "pauseTimes": 15,
            "pausedAt": 15,
            "pausedSeconds": 15,
            "sets": 15,
            "startedAt": 15,
            "workoutID": 15,
            "workoutName": 15,
        ],
    ]

    /// The entities a version stores, each with its property names sorted.
    private static func expected(in version: Int) -> [String: [String]] {
        firstShipped.reduce(into: [:]) { stored, entity in
            let gone = lastShipped[entity.key] ?? [:]
            let names = entity.value.filter { name, first in
                first <= version && version <= gone[name, default: .max]
            }.keys.sorted()
            if !names.isEmpty {
                stored[entity.key] = names
            }
        }
    }

    @Test("Every shipped schema version stores the entity and property names it shipped with")
    func shippedNames() {
        for (number, version) in Self.shipped.sorted(by: { $0.key < $1.key }) {
            let schema = Schema(versionedSchema: version)
            let stored = Dictionary(uniqueKeysWithValues: schema.entities.map { entity in
                (entity.name, entity.properties.map(\.name).sorted())
            })
            #expect(stored == Self.expected(in: number), "Version \(number)")
        }
    }
}

extension StoredNamesTests {
    /// Every property a version stopped storing, and the last version that stored it.
    private static let lastShipped: [String: [String: Int]] = [
        "StoredExercise": ["muscleGroup": 14],
        "StoredRoutine": [
            "editedAt": 16,
            "exercises": 16,
            "id": 16,
            "name": 16,
            "openedAt": 16,
        ],
        "StoredRoutineExercise": [
            "exerciseID": 16,
            "id": 16,
            "isRestAuto": 16,
            "isRoundRestAuto": 16,
            "position": 16,
            "reps": 16,
            "rest": 16,
            "roundRest": 16,
            "routine": 16,
            "seconds": 16,
            "sets": 16,
            "supersetID": 16,
            "weight": 16,
            "weightUnit": 16,
        ],
        "StoredSet": [
            "clockWhenLogged": 15,
            "exerciseID": 15,
            "exerciseName": 15,
            "id": 15,
            "loggedAt": 15,
            "plannedReps": 15,
            "plannedSeconds": 15,
            "plannedWeight": 15,
            "plannedWeightUnit": 15,
            "position": 15,
            "reps": 15,
            "restAdjustment": 15,
            "restSkippedAt": 15,
            "round": 15,
            "rowID": 15,
            "seconds": 15,
            "side": 15,
            "timeAdded": 15,
            "weight": 15,
            "weightUnit": 15,
            "workout": 15,
        ],
        "StoredWorkout": [
            "countAdded": 15,
            "countRound": 15,
            "countRowID": 15,
            "countSide": 15,
            "countStartClock": 15,
            "endedAt": 15,
            "healthActivity": 15,
            "healthWorkoutID": 15,
            "pauseTimes": 15,
            "pausedAt": 15,
            "pausedSeconds": 15,
            "routineID": 15,
            "routineName": 15,
            "sets": 15,
            "startedAt": 15,
        ],
    ]
}
