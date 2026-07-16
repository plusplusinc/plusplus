import Testing
import PlusPlusKit

@Suite("WorkoutMetric")
struct WorkoutMetricTests {
    @Test("Incrementing nil lands on the metric's default value")
    func incrementFromNil() {
        #expect(WorkoutMetric.weight.incremented(nil) == 45)
        #expect(WorkoutMetric.reps.incremented(nil) == 10)
        #expect(WorkoutMetric.duration.incremented(nil) == 30)
    }

    @Test("Decrementing nil also lands on the default value")
    func decrementFromNil() {
        #expect(WorkoutMetric.weight.decremented(nil) == 45)
        #expect(WorkoutMetric.reps.decremented(nil) == 10)
        #expect(WorkoutMetric.duration.decremented(nil) == 30)
    }

    @Test("Increment applies the metric's step")
    func incrementStep() {
        #expect(WorkoutMetric.weight.incremented(135) == 140)
        #expect(WorkoutMetric.reps.incremented(10) == 11)
        #expect(WorkoutMetric.duration.incremented(30) == 45)
    }

    @Test("A step override replaces the unit step, not the default or clamp")
    func stepOverride() {
        #expect(WorkoutMetric.weight.incremented(135, stepOverride: 2.5) == 137.5)
        #expect(WorkoutMetric.weight.decremented(135, stepOverride: 10) == 125)
        #expect(WorkoutMetric.weight.incremented(135, weightUnit: .kg, stepOverride: 1) == 136)
        // nil value still lands on the default, override or not.
        #expect(WorkoutMetric.weight.incremented(nil, stepOverride: 10) == 45)
        // clamping still applies.
        #expect(WorkoutMetric.weight.decremented(5, stepOverride: 10) == 0)
    }

    @Test("Every metric's step choices are positive, ascending, and non-empty")
    func stepChoicesWellFormed() {
        for metric in WorkoutMetric.allCases {
            for weightUnit in WeightUnit.allCases {
                for distanceUnit in DistanceUnit.allCases {
                    let choices = metric.stepChoices(weightUnit: weightUnit, distanceUnit: distanceUnit)
                    #expect(!choices.isEmpty, "\(metric) has no step choices")
                    let allPositive = choices.allSatisfy { $0.isFinite && $0 > 0 }
                    #expect(allPositive, "\(metric) step choices must be finite and positive")
                    let ascending = zip(choices, choices.dropFirst()).allSatisfy { $0 < $1 }
                    #expect(ascending, "\(metric) step choices must strictly ascend")
                }
            }
        }
    }

    @Test("Step choices are unit-aware for weight and distance")
    func stepChoicesUnitAware() {
        #expect(WorkoutMetric.weight.stepChoices(weightUnit: .lb).contains(2.5))
        #expect(WorkoutMetric.weight.stepChoices(weightUnit: .lb).contains(45))
        #expect(WorkoutMetric.weight.stepChoices(weightUnit: .kg).contains(1.25))
        #expect(WorkoutMetric.distance.stepChoices(distanceUnit: .meters).contains(50))
        #expect(WorkoutMetric.distance.stepChoices(distanceUnit: .miles).contains(0.25))
        // A choosable increment should be usable as a stepOverride and
        // move the value by exactly that amount.
        let choice = WorkoutMetric.incline.stepChoices().first!
        #expect(WorkoutMetric.incline.incremented(1, stepOverride: choice) == 1 + choice)
    }

    @Test("Values clamp at the range bounds")
    func clamping() {
        #expect(WorkoutMetric.weight.decremented(0) == 0)
        #expect(WorkoutMetric.reps.decremented(1) == 1)
        #expect(WorkoutMetric.weight.incremented(1000) == 1000)
        #expect(WorkoutMetric.duration.decremented(5) == 5)
    }

    @Test("Formatting drops trailing .0 and keeps real fractions")
    func formatting() {
        #expect(WorkoutMetric.weight.formatted(nil) == "—")
        #expect(WorkoutMetric.weight.formatted(135) == "135")
        #expect(WorkoutMetric.weight.formatted(137.5) == "137.5")
        #expect(WorkoutMetric.reps.formatted(8) == "8")
    }

    @Test("Nearest wheel value snaps to the wheel step")
    func nearestWheelValue() {
        #expect(WorkoutMetric.weight.nearestWheelValue(to: nil) == 45)
        #expect(WorkoutMetric.weight.nearestWheelValue(to: 137.4) == 137.5)
        #expect(WorkoutMetric.weight.nearestWheelValue(to: 136) == 135)
        #expect(WorkoutMetric.weight.nearestWheelValue(to: -20) == 0)
        #expect(WorkoutMetric.weight.nearestWheelValue(to: 5000) == 1000)
    }

    @Test("Wheel values span the full range at wheel-step granularity")
    func wheelValues() {
        let weightWheel = WorkoutMetric.weight.wheelValues
        #expect(weightWheel.first == 0)
        #expect(weightWheel.last == 1000)
        #expect(weightWheel.contains(2.5))

        let repsWheel = WorkoutMetric.reps.wheelValues
        #expect(repsWheel.first == 1)
        #expect(repsWheel.last == 100)
        #expect(repsWheel.count == 100)
    }

    @Test("Rest metric: 15s steps within 15...600, default 45")
    func restMetric() {
        // 45, not 90 (#369): transitions cover station switches now.
        #expect(WorkoutMetric.rest.incremented(nil) == 45)
        #expect(WorkoutMetric.rest.incremented(90) == 105)
        #expect(WorkoutMetric.rest.decremented(15) == 15)
        #expect(WorkoutMetric.rest.incremented(600) == 600)
        #expect(WorkoutMetric.rest.wheelValues.first == 15)
        #expect(WorkoutMetric.rest.wheelValues.last == 600)
    }

    @Test("Transition metric: 5s steps within 0...600, default 15 (#369)")
    func transitionMetric() {
        #expect(WorkoutMetric.transition.incremented(nil) == 15)
        #expect(WorkoutMetric.transition.incremented(15) == 20)
        // 0 is legal and means "no countdown at all".
        #expect(WorkoutMetric.transition.decremented(5) == 0)
        #expect(WorkoutMetric.transition.decremented(0) == 0)
        #expect(WorkoutMetric.transition.incremented(600) == 600)
        #expect(WorkoutMetric.transition.displayText(15) == "15 sec")
    }

    @Test("Rest and transition are block configuration, everything else tracks")
    func blockConfiguration() {
        #expect(WorkoutMetric.rest.isBlockConfiguration)
        #expect(WorkoutMetric.transition.isBlockConfiguration)
        let trackable = WorkoutMetric.allCases.filter { !$0.isBlockConfiguration }
        #expect(!trackable.isEmpty && !trackable.contains(.rest) && !trackable.contains(.transition))
    }

    @Test("Every wheel value formats to a stable label")
    func wheelValueFormatting() {
        let hasEmptyLabel = WorkoutMetric.weight.wheelValues
            .map { WorkoutMetric.weight.formatted($0) }
            .contains("")
        #expect(!hasEmptyLabel)
    }

    @Test("Duration covers cardio blocks up to an hour")
    func durationRange() {
        #expect(WorkoutMetric.duration.clamped(1500) == 1500)
        #expect(WorkoutMetric.duration.incremented(3600) == 3600)
        #expect(WorkoutMetric.duration.clamped(4000) == 3600)
    }

    @Test("Duration wheel granularity coarsens with the value")
    func durationWheelTiers() {
        let wheel = WorkoutMetric.duration.wheelValues
        #expect(wheel.first == 5)
        #expect(wheel.last == 3600)
        // 5 s steps for short holds, 15 s to ten minutes, whole minutes beyond.
        #expect(wheel.contains(45) && wheel.contains(115))
        #expect(wheel.contains(135) && !wheel.contains(125))
        #expect(wheel.contains(1500) && !wheel.contains(630))
        // Strictly increasing with no duplicates at the tier seams.
        let isSorted = zip(wheel, wheel.dropFirst()).allSatisfy { $0 < $1 }
        #expect(isSorted)
    }

    @Test("Nearest wheel value works on the tiered duration wheel")
    func durationNearestWheelValue() {
        #expect(WorkoutMetric.duration.nearestWheelValue(to: nil) == 30)
        #expect(WorkoutMetric.duration.nearestWheelValue(to: 1500) == 1500)
        #expect(WorkoutMetric.duration.nearestWheelValue(to: 631) == 660)
        #expect(WorkoutMetric.duration.nearestWheelValue(to: 9999) == 3600)
    }

    @Test("Durations of a minute or more render as m:ss with no unit")
    func durationFormatting() {
        #expect(WorkoutMetric.duration.formatted(45) == "45")
        #expect(WorkoutMetric.duration.unit(for: 45) == "sec")
        #expect(WorkoutMetric.duration.formatted(90) == "1:30")
        #expect(WorkoutMetric.duration.unit(for: 90) == "")
        #expect(WorkoutMetric.duration.formatted(1500) == "25:00")
        #expect(WorkoutMetric.duration.formatted(3600) == "60:00")
        #expect(WorkoutMetric.duration.displayText(45) == "45 sec")
        #expect(WorkoutMetric.duration.displayText(1500) == "25:00")
        #expect(WorkoutMetric.duration.displayText(nil) == "— sec")
        // Other metrics are untouched by the m:ss rule.
        #expect(WorkoutMetric.rest.formatted(90) == "90")
        #expect(WorkoutMetric.weight.displayText(135) == "135 lb")
    }
}
