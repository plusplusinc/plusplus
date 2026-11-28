import Foundation
import Testing
@testable import WorkoutStore

/// The type Apple Health gets for a workout: by the kind most of its exercises are, and for
/// strength by how many of its strength exercises hold a weight.
@Suite("Health activity")
struct HealthActivityTests {
    @Test("Each workout's type follows its exercises", arguments: [
        // Mostly weights, and an even split.
        (["Goblet squat", "Barbell back squat", "Push-up"], HealthActivity.traditionalStrength),
        (["Goblet squat", "Push-up"], .traditionalStrength),
        // Mostly bodyweight: a pull-up's bar, a band, and a balance board hold no weight.
        (["Push-up", "Pull-up", "Goblet squat"], .functionalStrength),
        (["Band pull-apart", "Face pull", "Balance board hold"], .functionalStrength),
        // Conditioning and stretching.
        (["Jumping jacks", "Burpee", "Goblet squat"], .highIntensityIntervals),
        (["Hamstring stretch", "Pigeon stretch", "Calf stretch"], .flexibility),
        // Nothing at all.
        ([], .traditionalStrength),
    ])
    func byKind(names: [String], activity: HealthActivity) throws {
        #expect(try HealthActivity(exercises: Exercise.builtIn(named: names)) == activity)
    }

    @Test(
        "A workout mixing kinds goes by the kind most of it is, a tie by Strength first",
        arguments: [
            // Strength with a stretch to end: the stretch leaves the weights' share alone.
            (
                ["Goblet squat", "Push-up", "Pull-up", "Hamstring stretch"],
                HealthActivity.functionalStrength,
            ),
            (
                [
                    "Barbell back squat",
                    "Barbell bench press",
                    "Hamstring stretch",
                    "Pigeon stretch",
                ],
                .traditionalStrength,
            ),
            // A kettlebell swing is conditioning, so its weight doesn't count toward strength's.
            (["Kettlebell swing", "Burpee", "Push-up", "Pull-up"], .functionalStrength),
            (["Burpee", "Hamstring stretch"], .highIntensityIntervals),
        ],
    )
    func mixed(names: [String], activity: HealthActivity) throws {
        #expect(try HealthActivity(exercises: Exercise.builtIn(named: names)) == activity)
    }

    @Test("An exercise in three rows counts three times, on the row and in Health alike")
    func repeatedExercise() throws {
        // Counted once per exercise, this would be strength: Push-up and Pull-up against Burpee.
        let names = ["Burpee", "Burpee", "Burpee", "Push-up", "Pull-up"]
        let workout = try Workout(exercises: names.map { try WorkoutExercise.builtIn($0) })
        let logged = LogFixture.workoutSession(daysAgo: 0, workout.exercises.map {
            LogFixture.set($0.exercise.id, .reps(10), row: $0.id)
        })
        #expect(workout.summary?.kind == .conditioning)
        #expect(HealthActivity(logged: logged.sets, in: .builtIn) == .highIntensityIntervals)
    }

    @Test("A finished workout's type counts each row it logged once, the deleted left out")
    func fromLogged() {
        func set(_ id: String, round: Int = 1, row: UUID = UUID()) -> LoggedSet {
            LogFixture.set(id, round: round, .reps(10), row: row)
        }
        // Push-up's three sets in one row count once, so the kettlebell holds half:
        // traditional. Counted by set it would be functional. The deleted exercise would tip
        // it either way.
        let pushUps = UUID()
        let logged = LogFixture.workoutSession(daysAgo: 0, [
            set("push-up", round: 1, row: pushUps),
            set("push-up", round: 2, row: pushUps),
            set("push-up", round: 3, row: pushUps),
            set("goblet-squat"),
            set("created:gone"),
        ])
        #expect(HealthActivity(logged: logged.sets, in: .builtIn) == .traditionalStrength)
    }

    @Test("A stored type reads back by its raw string, an unknown one as none")
    func rawValues() {
        // The strings stored: a renamed case would read every workout stored before as none.
        let stored: [String: HealthActivity] = [
            "traditionalStrength": .traditionalStrength,
            "functionalStrength": .functionalStrength,
            "highIntensityIntervals": .highIntensityIntervals,
            "flexibility": .flexibility,
        ]
        for (raw, activity) in stored {
            #expect(activity.rawValue == raw)
            #expect(HealthActivity(rawValue: raw) == activity)
        }
        #expect(HealthActivity(rawValue: "swimming") == nil)
    }
}
