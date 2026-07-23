import Foundation
import Testing
@testable import PlusPlusKit

@Suite("ExerciseModality")
struct ExerciseModalityTests {
    @Test("Gear-specific families win whatever the metrics say")
    func gearSpecific() {
        #expect(ExerciseModality.derive(equipmentNames: ["Rowing Machine"], metrics: [.distance, .duration, .pace]) == .rowing)
        #expect(ExerciseModality.derive(equipmentNames: ["Jump Rope"], metrics: [.duration]) == .jumpRope)
        #expect(ExerciseModality.derive(equipmentNames: ["Bicycle"], metrics: [.distance, .pace]) == .cycling)
        #expect(ExerciseModality.derive(equipmentNames: ["Stationary Bike"], metrics: [.duration, .calories]) == .cycling)
        #expect(ExerciseModality.derive(equipmentNames: ["Air Bike"], metrics: [.calories, .duration]) == .cycling)
    }

    @Test("Load wins over distance: carries and sled work read as strength")
    func loadedCarries() {
        #expect(ExerciseModality.derive(equipmentNames: ["Farmers Walk Handles"], metrics: [.weight, .distance, .duration]) == .strength)
        #expect(ExerciseModality.derive(equipmentNames: ["Sled"], metrics: [.weight, .distance]) == .strength)
    }

    @Test("Road and console metrics read as cardio")
    func cardio() {
        #expect(ExerciseModality.derive(equipmentNames: [], metrics: [.distance, .duration, .pace]) == .cardio)
        #expect(ExerciseModality.derive(equipmentNames: ["Treadmill"], metrics: [.speed, .incline, .duration]) == .cardio)
        #expect(ExerciseModality.derive(equipmentNames: ["Stair Climber"], metrics: [.duration, .calories]) == .cardio)
    }

    @Test("Everything else is strength, including duration-only holds")
    func strengthDefault() {
        #expect(ExerciseModality.derive(equipmentNames: ["Barbell"], metrics: [.weight, .reps]) == .strength)
        #expect(ExerciseModality.derive(equipmentNames: [], metrics: [.reps]) == .strength)
        // A plank tracks duration alone; derivation must NOT call it
        // cardio (or flexibility — that case is authored only).
        #expect(ExerciseModality.derive(equipmentNames: [], metrics: [.duration]) == .strength)
    }
}
