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

    @Test("A workout's row and the type Health gets read the same kind")
    func sameKindAsSummary() throws {
        let names = ["Burpee", "Jumping jacks", "Push-up", "Hamstring stretch"]
        let workout = try Workout(exercises: names.map { try WorkoutExercise.builtIn($0) })
        let exercises = try Exercise.builtIn(named: names)
        #expect(workout.summary?.kind == .conditioning)
        #expect(exercises.kind == .conditioning)
        #expect(HealthActivity(exercises: exercises) == .highIntensityIntervals)
    }

    @Test("A finished workout's type is from what it logged, each once, the deleted left out")
    func fromLogged() throws {
        func set(_ id: String, row: UUID = LogFixture.row) -> LoggedSet {
            LogFixture.set(id, .reps(10), row: row)
        }
        // Push-up in two rows counts once, so the kettlebell holds half: traditional. Counted
        // twice it would be functional. The deleted exercise would tip it either way.
        let logged = LogFixture.loggedWorkout(daysAgo: 0, [
            set("push-up"),
            set("goblet-squat"),
            set("push-up", row: UUID()),
            set("created:gone"),
        ])
        let workout = try HealthWorkout(
            finished: logged,
            in: .builtIn,
            resumedSeconds: 0,
            pausedSince: nil,
        )
        #expect(workout.activity == .traditionalStrength)
        let bodyweight = LogFixture.loggedWorkout(daysAgo: 0, [set("push-up"), set("pull-up")])
        let functional = try HealthWorkout(
            finished: bodyweight,
            in: .builtIn,
            resumedSeconds: 0,
            pausedSince: nil,
        )
        #expect(functional.activity == .functionalStrength)
    }
}
