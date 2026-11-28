import SwiftData
import Testing
@testable import WorkoutStore

/// SwiftData finds a phone's rows by the entity and property names they were stored under, so a
/// shipped version's names never change. The upgrade tests write each old shape with the same
/// in-code classes they open it with, so a name changed in every version at once passes them;
/// only a literal written down from the code as shipped catches it. Nothing else in this file
/// names a type a rename could touch, so a rename has no reason to edit it.
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
    ]

    /// Every stored entity's properties and the version each first shipped in, written down from
    /// the code at a8510b7. No version so far has removed or renamed one, so a version stores
    /// exactly the properties that shipped in it or before.
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
            "name": 8,
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
        "StoredWorkout": [
            "countAdded": 12,
            "countRound": 12,
            "countRowID": 12,
            "countSide": 12,
            "countStartClock": 12,
            "endedAt": 5,
            "healthActivity": 14,
            "healthWorkoutID": 14,
            "id": 5,
            "pauseTimes": 14,
            "pausedAt": 5,
            "pausedSeconds": 5,
            "routineID": 5,
            "routineName": 5,
            "sets": 6,
            "startedAt": 5,
        ],
    ]

    /// The entities a version stores, each with its property names sorted.
    private static func expected(in version: Int) -> [String: [String]] {
        firstShipped.compactMapValues { properties in
            let names = properties.filter { $0.value <= version }.keys.sorted()
            return names.isEmpty ? nil : names
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
