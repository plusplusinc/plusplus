import Foundation
import Testing
import PlusPlusKit

@Suite("Weight units")
struct WeightUnitTests {
    @Test("kg semantics: bar default, plate steps, microplate wheel")
    func kgSemantics() {
        #expect(WeightUnit.kg.defaultValue == 20)
        #expect(WeightUnit.kg.step == 2.5)
        #expect(WeightUnit.kg.wheelStep == 1.25)
        #expect(WeightUnit.lb.defaultValue == 45)
        #expect(WeightUnit.lb.step == 5)
        #expect(WeightUnit.lb.wheelStep == 2.5)
    }

    @Test("Weight stepping and defaults honor the unit; other metrics ignore it")
    func metricIntegration() {
        #expect(WorkoutMetric.weight.incremented(nil, weightUnit: .kg) == 20)
        #expect(WorkoutMetric.weight.incremented(100, weightUnit: .kg) == 102.5)
        #expect(WorkoutMetric.weight.decremented(100, weightUnit: .kg) == 97.5)
        #expect(WorkoutMetric.weight.nearestWheelValue(to: 61, weightUnit: .kg) == 61.25)
        #expect(WorkoutMetric.weight.displayText(100, weightUnit: .kg) == "100 kg")
        #expect(WorkoutMetric.weight.displayText(102.5, weightUnit: .kg) == "102.5 kg")

        // Defaults unchanged: no parameter still means pounds.
        #expect(WorkoutMetric.weight.incremented(nil) == 45)
        #expect(WorkoutMetric.weight.displayText(135) == "135 lb")

        // Unit is weight-only.
        #expect(WorkoutMetric.reps.incremented(10, weightUnit: .kg) == 11)
        #expect(WorkoutMetric.duration.displayText(1500, weightUnit: .kg) == "25:00")
        #expect(WorkoutMetric.rest.displayText(90, weightUnit: .kg) == "90 sec")
    }

    @Test("Bundle units field round-trips; absent means nil (pounds)")
    func bundleField() throws {
        let kg = ExportBundle(units: .kg, exercises: [], routines: [], sessions: [])
        let data = try InterchangeCodec.encode(kg)
        #expect(String(decoding: data, as: UTF8.self).contains("\"units\" : \"kg\""))
        let decoded = try InterchangeCodec.decode(ExportBundle.self, from: data)
        #expect(decoded.units == .kg)

        // A pre-units file (no units key) still decodes, as nil.
        let legacy = Data("""
        {"schemaVersion": 1, "exercises": [], "routines": [], "sessions": []}
        """.utf8)
        let old = try InterchangeCodec.decode(ExportBundle.self, from: legacy)
        #expect(old.units == nil)
    }
}
