import Testing
@testable import WorkoutStore

/// A workout's estimated length, muscles, kind, and equipment, and the bar's scale.
@Suite("Workout summary")
struct WorkoutSummaryTests {
    private static let rep = WorkoutSummary.secondsPerRep

    private static func row(
        _ name: String,
        sets: Int,
        _ target: SetTarget,
        rest: Int,
    ) throws -> WorkoutExercise {
        try WorkoutExercise.builtIn(name) {
            $0.sets = sets
            $0.target = target
            $0.rest = .byHand(rest)
        }
    }

    @Test("A plain row takes its sets' work and the rests between them, none after the last")
    func plainRow() throws {
        let workout = try Workout(exercises: [Self.row(
            "Goblet squat",
            sets: 3,
            .reps(10),
            rest: 60,
        )])
        #expect(workout.estimatedSeconds == 3 * 10 * Self.rep + 2 * 60 + LiveWorkout.startIn)
    }

    @Test("A row's rest after its last set is the way to the next exercise, counted once")
    func twoRows() throws {
        let workout = try Workout(exercises: [
            Self.row("Goblet squat", sets: 2, .reps(10), rest: 60),
            Self.row("Push-up", sets: 1, .reps(10), rest: 90),
        ])
        let startIns = 2 * LiveWorkout.startIn
        #expect(workout.estimatedSeconds == 3 * 10 * Self.rep + 2 * 60 + startIns)
    }

    @Test("A per-side row takes both sides a set, with no rest between them")
    func perSide() throws {
        let row = try Self.row("Bulgarian split squat", sets: 2, .reps(8), rest: 60)
        #expect(row.exercise.isPerSide)
        let workout = Workout(exercises: [row])
        let startIns = LiveWorkout.startIn + 2 * LiveWorkout.startInSides
        #expect(workout.estimatedSeconds == 4 * 8 * Self.rep + 60 + startIns)
    }

    @Test("A timed set takes its seconds and the Start in before it")
    func timed() throws {
        let workout = try Workout(exercises: [Self.row(
            "Plank",
            sets: 1,
            .time(seconds: 45),
            rest: 0,
        )])
        #expect(workout.estimatedSeconds == 45 + LiveWorkout.startIn)
    }

    @Test("The estimate is the live workout's own order and rests, a superset included")
    func matchesSetOrder() throws {
        var workout = try Workout(exercises: [
            Self.row("Dumbbell bench press", sets: 3, .reps(10), rest: 90),
            Self.row("Dumbbell row", sets: 3, .reps(12), rest: 90),
            Self.row("Plank", sets: 2, .time(seconds: 30), rest: 30),
        ])
        workout.join(workout.exercises[0].id, .below)
        let order = workout.setOrder
        var expected = 0
        for (index, set) in order.enumerated() {
            let row = try #require(workout.exercises.first { $0.id == set.row })
            switch row.plan.target {
            case let .reps(reps): expected += reps * Self.rep
            case let .time(seconds): expected += seconds
            }
            expected += workout.startIn(before: set)
            expected += workout.rest(
                after: set,
                before: order.indices
                    .contains(index + 1) ? order[index + 1] : nil,
            )
        }
        #expect(workout.estimatedSeconds == expected)
    }

    @Test("Adding a set never shortens a workout")
    func longer() throws {
        let short = try Workout(exercises: [Self.row("Goblet squat", sets: 2, .reps(10), rest: 60)])
        let long = try Workout(exercises: [Self.row("Goblet squat", sets: 3, .reps(10), rest: 60)])
        #expect(long.estimatedSeconds > short.estimatedSeconds)
    }

    @Test("Minutes read to the nearest 5, never under 5")
    func minutes() {
        #expect(Self.summary(seconds: 37 * 60).minutes == 35)
        #expect(Self.summary(seconds: 38 * 60).minutes == 40)
        #expect(Self.summary(seconds: 60).minutes == 5)
    }

    @Test("Shares go by sets, most first, a tie in body order, and sum to 1")
    func shares() throws {
        let summary = try #require(Workout(exercises: [
            Self.row("Goblet squat", sets: 6, .reps(10), rest: 60),
            Self.row("Push-up", sets: 2, .reps(10), rest: 60),
            Self.row("Dumbbell row", sets: 2, .reps(10), rest: 60),
        ]).summary)
        #expect(summary.muscles.first?.group == .legs)
        #expect(abs(summary.muscles.map(\.share).reduce(0, +) - 1) < 1e-9)
        for (one, next) in zip(summary.muscles, summary.muscles.dropFirst()) {
            #expect(one.share >= next.share)
            if one.share == next.share {
                let order = MuscleGroup.allCases
                #expect(try #require(order.firstIndex(of: one.group)) <
                    #require(order.firstIndex(of: next.group)))
            }
        }
    }

    @Test("Past the limit, each muscle is its own segment, every one no longer than the last")
    func segments() {
        let summary = Self.summary(groups: [.chest, .back, .legs, .arms, .core])
        let (named, rest) = summary.segments(limit: 3)
        #expect(named.count == 3)
        #expect(rest.count == 2)
        let shares = (named + rest).map(\.share)
        #expect(zip(shares, shares.dropFirst()).allSatisfy { $0 >= $1 })
        #expect(Self.summary(groups: [.chest, .back, .legs]).segments(limit: 3).rest.isEmpty)
    }

    @Test("The kind is the most exercises', a tie going Strength; equipment once each")
    func kindAndEquipment() throws {
        let summary = try #require(Workout(exercises: [
            .builtIn("Goblet squat"),
            .builtIn("Dumbbell row"),
            .builtIn("Pigeon stretch"),
            .builtIn("Hamstring stretch"),
        ]).summary)
        #expect(summary.kind == .strength)
        #expect(Set(summary.equipment).isSuperset(of: [.dumbbells, .kettlebell]))
        #expect(summary.equipment == Equipment.allCases.filter(summary.equipment.contains))
        let stretch = try #require(Workout(exercises: [.builtIn("Pigeon stretch")]).summary)
        #expect(stretch.kind.workoutWord == "Stretching")
        #expect(stretch.equipment.isEmpty)
        #expect(Workout().summary == nil)
    }

    @Test("Past the floor, the longest workout shown fills the bar, by the minutes rows read")
    func scaleOverFloor() {
        let longest = Self.summary(seconds: (WorkoutSummary.shortestFullBar + 17) * 60)
        let short = Self.summary(seconds: 600)
        let scale = WorkoutSummary.fullBarMinutes(among: [longest, short])
        #expect(scale == longest.minutes)
        #expect(longest.fill(of: scale) == 1)
        #expect(short.fill(of: scale) == Double(short.minutes) / Double(longest.minutes))
        // Two workouts reading the same length draw the same bar.
        let near = Self.summary(seconds: longest.seconds - 60)
        #expect(near.fill(of: scale) == longest.fill(of: scale))
    }

    @Test("Under the floor, or with nothing shown, a full bar is the floor; at it, full")
    func scaleFloor() {
        let floor = WorkoutSummary.shortestFullBar
        let under = Self.summary(seconds: (floor - 10) * 60)
        #expect(WorkoutSummary.fullBarMinutes(among: [under]) == floor)
        #expect(under.fill(of: floor) < 1)
        let at = Self.summary(seconds: floor * 60 - 20)
        #expect(at.fill(of: WorkoutSummary.fullBarMinutes(among: [at])) == 1)
        #expect(WorkoutSummary.fullBarMinutes(among: [WorkoutSummary]()) == floor)
    }

    @Test("Leaving out the longest workout shortens the scale, down to the floor")
    func scaleFollowsList() {
        let long = Self.summary(seconds: 75 * 60)
        let mid = Self.summary(seconds: 45 * 60)
        let all = WorkoutSummary.fullBarMinutes(among: [long, mid])
        let fewer = WorkoutSummary.fullBarMinutes(among: [mid])
        #expect(fewer < all)
        #expect(fewer >= WorkoutSummary.shortestFullBar)
    }

    static func summary(
        seconds: Int = 1800,
        groups: [MuscleGroup] = [.legs],
        equipment: [Equipment] = [],
    ) -> WorkoutSummary {
        WorkoutSummary(
            seconds: seconds,
            muscles: groups.map { .init(group: $0, share: 1 / Double(groups.count)) },
            kind: .strength,
            equipment: equipment,
        )
    }
}
