import Foundation
import Testing
import PlusPlusKit

@Suite("MetricProfile")
struct MetricProfileTests {
    @Test("Profiles normalize to canonical order, dedupe, and exclude block configuration")
    func normalization() {
        let profile = MetricProfile([.resistance, .duration, .distance, .duration, .rest, .transition, .pace])
        #expect(profile.metrics == [.distance, .duration, .pace, .resistance])
    }

    @Test("Legacy types derive the classic profiles and map back")
    func legacyBridge() {
        #expect(MetricProfile.derived(from: .weightReps) == .weightReps)
        #expect(MetricProfile.derived(from: .duration) == .durationOnly)
        #expect(MetricProfile.weightReps.legacyType == .weightReps)
        #expect(MetricProfile.durationOnly.legacyType == .duration)
        // Bodyweight rep work still speaks weightReps to old readers.
        #expect(MetricProfile.repsOnly.legacyType == .weightReps)
        // A rower profile has no reps → duration for old readers.
        #expect(MetricProfile([.distance, .duration, .pace]).legacyType == .duration)
    }

    @Test("Validity requires a work metric")
    func validity() {
        #expect(MetricProfile([.weight]).isValid == false)
        #expect(MetricProfile([.resistance, .incline]).isValid == false)
        #expect(MetricProfile([.reps]).isValid)
        #expect(MetricProfile([.distance]).isValid)
        #expect(MetricProfile([.calories]).isValid)
        #expect(MetricProfile([.duration]).isValid)
    }

    @Test("The driver is the highest-priority work metric WITH a target")
    func driverFollowsTargets() {
        let rower = MetricProfile([.distance, .duration, .pace, .resistance])
        // A 2000 m piece: distance targeted → distance drives, time is
        // an outcome.
        #expect(rower.driver(targets: { $0 == .distance ? 2000 : nil }) == .distance)
        // A 20-minute steady piece: duration targeted → the auto-timer.
        #expect(rower.driver(targets: { $0 == .duration ? 1200 : nil }) == .duration)
        // Both targeted: distance outranks duration (erg pieces are
        // distance-first; the goal time is an annotation).
        #expect(rower.driver(targets: { [.distance, .duration].contains($0) ? 1 : nil }) == .distance)
        // Nothing targeted: first tracked work metric.
        #expect(rower.driver(targets: { _ in nil }) == .distance)
        // Reps always outrank cardio work metrics when tracked.
        let hybrid = MetricProfile([.reps, .distance])
        #expect(hybrid.driver(targets: { _ in 5 }) == .reps)
    }

    @Test("Codec round-trips and normalizes on decode")
    func codec() throws {
        let profile = MetricProfile([.distance, .pace], distanceUnit: .miles)
        let decoded = MetricProfile.decode(from: profile.encoded())
        #expect(decoded == profile)

        // Hand-written JSON: misordered metrics, unknown metric, no unit.
        let json = Data(#"{"metrics":["pace","warp","distance"]}"#.utf8)
        let lenient = try JSONDecoder().decode(MetricProfile.self, from: json)
        #expect(lenient.metrics == [.distance, .pace])
        #expect(lenient.distanceUnit == .meters)
    }

    @Test("isOutdoor round-trips and a pre-outdoor blob decodes to false")
    func outdoorFlag() throws {
        let run = MetricProfile([.distance, .duration, .pace], distanceUnit: .miles, isOutdoor: true)
        #expect(run.isOutdoor)
        #expect(MetricProfile.decode(from: run.encoded()) == run)

        // A blob written before the flag existed (no isOutdoor key) is an
        // indoor profile, not a crash.
        let legacy = Data(#"{"metrics":["distance","pace"],"distanceUnit":"mi"}"#.utf8)
        let decoded = try JSONDecoder().decode(MetricProfile.self, from: legacy)
        #expect(decoded.isOutdoor == false)

        // The flag participates in equality — same metrics, different
        // outdoor-ness are different profiles.
        #expect(MetricProfile([.distance], isOutdoor: true) != MetricProfile([.distance]))
    }

    @Test("MetricValues encodes nil when empty and drops unknown raw keys")
    func valueBags() {
        #expect(MetricValues.encode([:]) == nil)
        let values: [WorkoutMetric: Double] = [.distance: 2000, .resistance: 5]
        #expect(MetricValues.decode(MetricValues.encode(values)) == values)
        #expect(MetricValues.fromRaw(["distance": 500, "warp": 9]) == [.distance: 500])
        #expect(MetricValues.toRaw([:]) == nil)
    }
}

@Suite("New metric semantics")
struct NewMetricSemanticsTests {
    @Test("Pace formats as clock time with the unit's reference")
    func paceFormatting() {
        #expect(WorkoutMetric.pace.formatted(118) == "1:58")
        #expect(WorkoutMetric.pace.displayText(125, distanceUnit: .meters) == "2:05 /500m")
        #expect(WorkoutMetric.pace.displayText(540, distanceUnit: .miles) == "9:00 /mi")
        #expect(WorkoutMetric.pace.displayText(330, distanceUnit: .kilometers) == "5:30 /km")
    }

    @Test("Level-like metrics read label-first; incline binds tight")
    func labelFirstDisplay() {
        #expect(WorkoutMetric.resistance.displayText(7) == "lvl 7")
        #expect(WorkoutMetric.rpe.displayText(8.5) == "RPE 8.5")
        #expect(WorkoutMetric.incline.displayText(3) == "3%")
        #expect(WorkoutMetric.incline.displayText(nil) == "—")
        #expect(WorkoutMetric.power.displayText(150) == "150 W")
        #expect(WorkoutMetric.calories.displayText(15) == "15 cal")
    }

    @Test("Distance semantics ride the DistanceUnit")
    func distanceUnits() {
        #expect(WorkoutMetric.distance.incremented(500) == 550)
        #expect(WorkoutMetric.distance.incremented(3, distanceUnit: .miles) == 3.25)
        #expect(WorkoutMetric.distance.displayText(2000) == "2000 m")
        #expect(WorkoutMetric.distance.displayText(3.25, distanceUnit: .miles) == "3.25 mi")
        #expect(WorkoutMetric.distance.defaultValue(weightUnit: .lb, distanceUnit: .kilometers) == 5)
        // Meters wheel is tiered — fine grain early, coarse late, and
        // interval staples stay reachable.
        let wheel = WorkoutMetric.distance.wheelValues(weightUnit: .lb, distanceUnit: .meters)
        #expect(wheel.contains(400))
        #expect(wheel.contains(2000))
        #expect(wheel.count < 500)
    }

    @Test("Height and assistance ride the weight unit")
    func weightUnitRiders() {
        #expect(WorkoutMetric.height.displayText(24) == "24 in")
        #expect(WorkoutMetric.height.displayText(60, weightUnit: .kg) == "60 cm")
        #expect(WorkoutMetric.height.step(weightUnit: .kg) == 5)
        #expect(WorkoutMetric.assistance.incremented(60) == 65)
        #expect(WorkoutMetric.assistance.incremented(60, weightUnit: .kg) == 62.5)
        #expect(WorkoutMetric.assistance.incremented(60, stepOverride: 10) == 70)
    }

    @Test("Improvement directions: up for work, down for pace/assist, neutral for settings")
    func directions() {
        #expect(WorkoutMetric.weight.improvementDirection == .up)
        #expect(WorkoutMetric.distance.improvementDirection == .up)
        #expect(WorkoutMetric.pace.improvementDirection == .down)
        #expect(WorkoutMetric.assistance.improvementDirection == .down)
        #expect(WorkoutMetric.resistance.improvementDirection == .neutral)
        #expect(WorkoutMetric.speed.improvementDirection == .neutral)
        #expect(WorkoutMetric.rpe.improvementDirection == .neutral)
    }

    @Test("Original metrics keep their exact semantics")
    func originalsUntouched() {
        #expect(WorkoutMetric.weight.incremented(135) == 140)
        #expect(WorkoutMetric.duration.formatted(1500) == "25:00")
        #expect(WorkoutMetric.weight.displayText(137.5) == "137.5 lb")
        #expect(WorkoutMetric.rest.displayText(90) == "90 sec")
    }
}

@Suite("MetricSummary")
struct MetricSummaryTests {
    @Test("Classic rep work keeps its idiomatic shape")
    func classicLine() {
        let line = MetricSummary.line(profile: .weightReps) { metric in
            switch metric {
            case .weight: 135
            case .reps: 10
            default: nil
            }
        }
        #expect(line == "10 reps @ 135 lb")
        // Zero weight is bodyweight — no load part.
        let bare = MetricSummary.line(profile: .weightReps) { $0 == .reps ? 12 : 0 }
        #expect(bare == "12 reps")
    }

    @Test("repsText carries target ranges a Double can't")
    func repsRange() {
        let line = MetricSummary.line(profile: .weightReps, repsText: "8–10") { metric in
            metric == .weight ? 25 : nil
        }
        #expect(line == "8–10 reps @ 25 lb")
    }

    @Test("Assistance names itself so it can't read as added load")
    func assistance() {
        let line = MetricSummary.line(profile: MetricProfile([.assistance, .reps])) { metric in
            switch metric {
            case .assistance: 60
            case .reps: 8
            default: nil
            }
        }
        #expect(line == "8 reps @ 60 lb assist")
    }

    @Test("Cardio lines join tracked values in canonical order")
    func cardioLine() {
        let rower = MetricProfile([.distance, .duration, .pace, .resistance])
        let line = MetricSummary.line(profile: rower) { metric in
            switch metric {
            case .distance: 2000
            case .duration: 472
            case .pace: 118
            case .resistance: 5
            default: nil
            }
        }
        #expect(line == "2000 m · 7:52 · 1:58 /500m · lvl 5")
        #expect(MetricSummary.line(profile: rower) { _ in nil } == nil)
    }
}

@Suite("RoutineDiff (flexible metrics)")
struct FlexibleDiffTests {
    @Test("A faster pace is an improvement — up-kind, negative arithmetic")
    func paceImprovement() {
        let target = RoutineDiff.Target(name: "Rowing", extras: [.pace: 115], distanceUnit: .meters)
        let prior = RoutineDiff.Prior(extras: [.pace: 120])
        let delta = RoutineDiff.delta(target: target, prior: prior)
        #expect(delta == .pace(-5, .meters))
        let segments = RoutineDiff.summary(deltas: [delta])
        #expect(segments == [.init(kind: .up, text: "−0:05 /500m")])
    }

    @Test("A slower pace stays quiet (anti-shame, generalized)")
    func paceRegression() {
        let target = RoutineDiff.Target(name: "Rowing", extras: [.pace: 130])
        let prior = RoutineDiff.Prior(extras: [.pace: 120])
        #expect(RoutineDiff.delta(target: target, prior: prior) == .unchanged)
    }

    @Test("Distance gains speak the exercise's own unit")
    func distanceGain() {
        let target = RoutineDiff.Target(name: "Run", extras: [.distance: 3.5], distanceUnit: .miles)
        let prior = RoutineDiff.Prior(extras: [.distance: 3])
        let delta = RoutineDiff.delta(target: target, prior: prior)
        #expect(delta == .distance(0.5, .miles))
        #expect(RoutineDiff.summary(deltas: [delta]) == [.init(kind: .up, text: "+0.5 mi")])
    }

    @Test("Weight still outranks everything; settings never diff")
    func priorityAndNeutrality() {
        let target = RoutineDiff.Target(
            name: "Sled Push",
            weight: 100,
            extras: [.distance: 50, .resistance: 9]
        )
        let prior = RoutineDiff.Prior(weight: 90, extras: [.distance: 25, .resistance: 3])
        #expect(RoutineDiff.delta(target: target, prior: prior) == .weight(10))

        // Resistance alone moving produces no delta — it's a setting.
        let settingOnly = RoutineDiff.Target(name: "Bike", extras: [.resistance: 9])
        let settingPrior = RoutineDiff.Prior(extras: [.resistance: 3])
        #expect(RoutineDiff.delta(target: settingOnly, prior: settingPrior) == .unchanged)
    }

    @Test("Classic inputs produce classic outputs (regression guard)")
    func classicUnchanged() {
        let weightUp = RoutineDiff.delta(
            target: .init(name: "Bench", weight: 140, reps: 8),
            prior: .init(weight: 135, reps: 8)
        )
        #expect(weightUp == .weight(5))
        let durationUp = RoutineDiff.delta(
            target: .init(name: "Plank", isDuration: true, durationSeconds: 75),
            prior: .init(durationSeconds: 60)
        )
        #expect(durationUp == .duration(15))
        #expect(RoutineDiff.delta(target: .init(name: "New"), prior: nil) == .new)
    }

    @Test("Less assistance is an improvement; more stays quiet")
    func assistanceImprovement() {
        let delta = RoutineDiff.delta(
            target: .init(name: "Assisted Pull-Up", reps: 8, extras: [.assistance: 50]),
            prior: .init(reps: 8, extras: [.assistance: 60])
        )
        #expect(delta == .assistance(-10))
        #expect(RoutineDiff.summary(deltas: [delta]) == [.init(kind: .up, text: "−10 lb assist")])
        // More assistance is a regression — silent (anti-shame).
        let worse = RoutineDiff.delta(
            target: .init(name: "Assisted Pull-Up", extras: [.assistance: 70]),
            prior: .init(extras: [.assistance: 60])
        )
        #expect(worse == .unchanged)
    }

    @Test("A taller box is an improvement in the weight unit's length")
    func heightImprovement() {
        let delta = RoutineDiff.delta(
            target: .init(name: "Box Jump", extras: [.height: 24]),
            prior: .init(extras: [.height: 20])
        )
        #expect(delta == .height(4))
        #expect(RoutineDiff.summary(deltas: [delta]) == [.init(kind: .up, text: "+4 in")])
        #expect(RoutineDiff.summary(deltas: [delta], weightUnit: .kg) == [.init(kind: .up, text: "+4 cm")])
    }

    @Test("Calories and power gains render with their units")
    func caloriesAndPower() {
        let cal = RoutineDiff.delta(
            target: .init(name: "Air Bike", extras: [.calories: 20]),
            prior: .init(extras: [.calories: 15])
        )
        #expect(RoutineDiff.summary(deltas: [cal]) == [.init(kind: .up, text: "+5 cal")])
        let power = RoutineDiff.delta(
            target: .init(name: "Bike", extras: [.power: 210]),
            prior: .init(extras: [.power: 200])
        )
        #expect(RoutineDiff.summary(deltas: [power]) == [.init(kind: .up, text: "+10 W")])
    }
}

@Suite("Interchange (flexible metrics)")
struct FlexibleInterchangeTests {
    private func bundle(
        exercises: [ExerciseDTO] = [],
        routines: [RoutineDTO] = [],
        sessions: [SessionDTO] = []
    ) -> ExportBundle {
        ExportBundle(exercises: exercises, routines: routines, sessions: sessions)
    }

    @Test("New fields survive a codec round-trip")
    func roundTrip() throws {
        let exercise = ExerciseDTO(
            name: "Rowing",
            muscleGroup: .fullBody,
            exerciseType: .duration,
            equipment: ["Rowing Machine"],
            metrics: ["distance", "duration", "pace", "resistance"],
            distanceUnit: .meters,
            extraDefaults: ["distance": 2000, "resistance": 5]
        )
        let routine = RoutineDTO(
            name: "Erg Intervals",
            restSeconds: 90,
            groups: [.init(
                sets: 4,
                exercises: [.init(exercise: "Rowing", extraTargets: ["distance": 500, "pace": 118])],
                restSeconds: 120
            )]
        )
        let session = SessionDTO(
            routineName: "Erg Intervals",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_003_600),
            restSeconds: 90,
            sets: [.init(
                order: 0, groupIndex: 0, setNumber: 1,
                exerciseName: "Rowing", exerciseType: .duration,
                extraTargets: ["distance": 500],
                extraActuals: ["distance": 500, "pace": 116],
                restSecondsOverride: 120
            )]
        )
        let original = bundle(exercises: [exercise], routines: [routine], sessions: [session])
        let data = try InterchangeCodec.encode(original)
        let decoded = try InterchangeCodec.decode(ExportBundle.self, from: data)
        #expect(decoded == original)
        #expect(InterchangeValidator.validate(original).isEmpty)
    }

    @Test("Old bundles decode with every new field absent")
    func oldBundlesUnchanged() throws {
        let exercise = ExerciseDTO(
            name: "Bench Press", muscleGroup: .chest,
            exerciseType: .weightReps, equipment: ["Barbell", "Bench"]
        )
        let original = bundle(exercises: [exercise])
        let decoded = try InterchangeCodec.decode(
            ExportBundle.self, from: InterchangeCodec.encode(original)
        )
        #expect(decoded.exercises[0].metrics == nil)
        #expect(decoded.exercises[0].distanceUnit == nil)
        #expect(decoded.exercises[0].extraDefaults == nil)
    }

    @Test("The validator rejects unknown metrics, shadowed fields, and bad rests")
    func validatorChecks() {
        let bad = bundle(
            exercises: [ExerciseDTO(
                name: "Custom", muscleGroup: .fullBody,
                exerciseType: .weightReps, equipment: [],
                metrics: ["weight", "warp"],
                extraDefaults: ["weight": 45, "resistence": 5]
            )],
            routines: [RoutineDTO(
                name: "R", restSeconds: 90,
                groups: [.init(
                    sets: 3,
                    exercises: [.init(exercise: "Custom", extraTargets: ["duration": 30])],
                    restSeconds: 5
                )]
            )]
        )
        let messages = InterchangeValidator.validate(bad).map(\.message)
        #expect(messages.contains { $0.contains("metrics.warp") })
        // "weight" in metrics is fine (profile membership) but weight-only
        // is invalid without a work metric alongside the unknown one.
        #expect(messages.contains { $0.contains("work metric") })
        #expect(messages.contains { $0.contains("extraDefaults.weight") })
        #expect(messages.contains { $0.contains("extraDefaults.resistence") })
        #expect(messages.contains { $0.contains("extraTargets.duration") })
        #expect(messages.contains { $0.contains("restSeconds 5") })
    }

    @Test("exerciseType must agree with the declared metrics")
    func typeConsistency() {
        let inconsistent = bundle(exercises: [ExerciseDTO(
            name: "Rowing", muscleGroup: .fullBody,
            exerciseType: .weightReps, equipment: [],
            metrics: ["distance", "duration"]
        )])
        let messages = InterchangeValidator.validate(inconsistent).map(\.message)
        #expect(messages.contains { $0.contains("disagrees with metrics") })
    }
}

@Suite("WatchSync (flexible metrics)")
struct FlexibleWatchSyncTests {
    @Test("Steps round-trip extras, unit, and rest override")
    func stepRoundTrip() throws {
        let step = WatchSync.Step(
            exerciseName: "Rowing", groupIndex: 0, setNumber: 1,
            isDuration: true,
            extraTargets: ["distance": 500, "pace": 118],
            distanceUnit: .meters,
            restSecondsOverride: 120
        )
        let decoded = try WatchSync.decode(WatchSync.Step.self, from: WatchSync.encode(step))
        #expect(decoded == step)
    }

    @Test("A pre-profile payload decodes with the new fields nil")
    func oldPayload() throws {
        let json = Data("""
        {"exerciseName":"Bench Press","groupIndex":0,"setNumber":1,
         "isDuration":false,"targetWeight":135,"targetRepsLower":8}
        """.utf8)
        let decoded = try WatchSync.decode(WatchSync.Step.self, from: json)
        #expect(decoded.extraTargets == nil)
        #expect(decoded.distanceUnit == nil)
        #expect(decoded.restSecondsOverride == nil)
    }
}
