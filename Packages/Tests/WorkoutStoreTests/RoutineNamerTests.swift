import Synchronization
import Testing
@testable import WorkoutStore

@Suite("Routine namer")
struct RoutineNamerTests {
    private static func exercises(_ names: String...) throws -> [Exercise] {
        try names.map { name in try #require(Exercise.builtIn.first { $0.name == name }) }
    }

    private static func namer(answering answer: Result<String, any Error>) -> RoutineNamer {
        RoutineNamer(isAvailable: { true }, respond: { _ in try answer.get() })
    }

    private struct ModelError: Error { }

    @Test("An unavailable model gives the muscle-group name without asking")
    func unavailable() async throws {
        let asks = Atomic(0)
        let namer = RoutineNamer(isAvailable: { false }, respond: { _ in
            asks.add(1, ordering: .relaxed)
            return "Leg day"
        })
        #expect(try await namer.name(for: Self.exercises("Goblet squat")) == "Legs")
        #expect(asks.load(ordering: .relaxed) == 0)
    }

    @Test("A model error gives the muscle-group name")
    func modelError() async throws {
        let namer = Self.namer(answering: .failure(ModelError()))
        let exercises = try Self.exercises("Pull-up", "Barbell bench press")
        #expect(await namer.name(for: exercises) == "Chest and back")
    }

    @Test("The model's answer is used, cleaned")
    func answerUsed() async throws {
        let namer = Self.namer(answering: .success(" \"leg day.\" \n"))
        #expect(try await namer.name(for: Self.exercises("Goblet squat")) == "Leg day")
    }

    @Test("An empty or overlong answer gives the muscle-group name", arguments: [
        "", " . ", String(repeating: "Squat ", count: 10),
    ])
    func unusableAnswer(answer: String) async throws {
        let namer = Self.namer(answering: .success(answer))
        #expect(try await namer.name(for: Self.exercises("Goblet squat")) == "Legs")
    }

    @Test("A cancelled ask gives nothing")
    func cancelled() async throws {
        let namer = Self.namer(answering: .failure(CancellationError()))
        #expect(try await namer.name(for: Self.exercises("Goblet squat")) == nil)
    }

    @Test("No exercises get no name, without asking")
    func noExercises() async {
        #expect(await Self.namer(answering: .success("Leg day")).name(for: []) == nil)
    }

    @Test("The model's first line is the name")
    func firstLine() {
        #expect(RoutineNamer.cleaned("\nleg day\nA routine for legs.") == "Leg day")
    }

    @Test("A name that runs past one title line gives the muscle-group name")
    func overlongAnswer() async throws {
        let namer = Self.namer(answering: .success("Lower body strength builder"))
        #expect(try await namer.name(for: Self.exercises("Goblet squat")) == "Legs")
    }

    @Test("A bare group gets its day, and a group that isn't there gives the focus's name")
    func answerKeptHonest() async throws {
        let core = try Self.exercises("Plank", "Dead bug")
        #expect(await Self.namer(answering: .success("core")).name(for: core) == "Core day")
        #expect(await Self.namer(answering: .success("Steady core")).name(for: core)
            == "Steady core")
        #expect(await Self.namer(answering: .success("Legs and core")).name(for: core)
            == "Core day")
    }

    @Test("The prompt lists each exercise once, with its group")
    func prompt() throws {
        let exercises = try Self.exercises("Pull-up", "Goblet squat", "Pull-up")
        #expect(RoutineNamer
            .prompt(for: exercises) ==
            "Exercises:\n- Pull-up (back)\n- Goblet squat (legs)\nFocus: back and legs")
    }
}
