import Foundation
import Testing
import PlusPlusKit

/// The fixtures under Fixtures/ are the language-neutral conformance suite
/// for interchange schema v1 — any future port (Go, TypeScript, …) or
/// third-party implementation should pass the equivalent of these checks.
@Suite("Conformance fixtures")
struct ConformanceTests {
    private func fixtureData(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
    }

    @Test("Valid fixture decodes, validates clean, and round-trips")
    func validFixture() throws {
        let data = try fixtureData("conformance-valid")
        let bundle = try InterchangeCodec.decode(ExportBundle.self, from: data)

        #expect(bundle.schemaVersion == 1)
        #expect(bundle.exercises.map(\.name) == ["Band Pulses", "Plank Hold", "Trail Run"])
        #expect(bundle.exercises.first?.defaultReps == 15)
        #expect(bundle.exercises.first?.defaultRepsUpper == 20)
        #expect(bundle.exercises.last?.isOutdoor == true)
        #expect(bundle.routines.first?.groups.count == 2)
        #expect(bundle.sessions.first?.sets.count == 2)
        #expect(bundle.sessions.last?.run?.distanceMeters == 5023.4)
        #expect(bundle.sessions.last?.run?.movingSeconds == 1732)
        #expect(bundle.sessions.last?.sets.first?.isOutdoor == true)
        #expect(InterchangeValidator.validate(bundle).isEmpty)

        // Semantic round-trip: encode → decode reproduces the value exactly.
        let reencoded = try InterchangeCodec.encode(bundle)
        let decodedAgain = try InterchangeCodec.decode(ExportBundle.self, from: reencoded)
        #expect(decodedAgain == bundle)

        // And the canonical encoding is a fixed point: encoding the decoded
        // canonical form yields byte-identical output.
        let third = try InterchangeCodec.encode(decodedAgain)
        #expect(third == reencoded)
    }

    @Test("Invalid fixture is caught by the validator with the expected issues")
    func invalidFixture() throws {
        let data = try fixtureData("conformance-invalid")
        let bundle = try InterchangeCodec.decode(ExportBundle.self, from: data)
        // Opt into reference checking so the fixture's absent reference flags.
        let messages = InterchangeValidator.validate(bundle, knownExerciseNames: [])
            .map(\.message).joined(separator: "; ")

        #expect(messages.contains("duplicate exercise name"))
        #expect(messages.contains("restSeconds 5 outside 15...600"))
        #expect(messages.contains("sets 0 outside 1...20"))
        #expect(messages.contains("unresolved exercise reference"))
        #expect(messages.contains("repsUpper 15 must exceed reps 20"))
        #expect(messages.contains("defaultReps 0 outside 1...100"))
        #expect(messages.contains("defaultRepsUpper without defaultReps"))
        #expect(messages.contains("isOutdoor without a distance or pace metric"))
        #expect(messages.contains("run.distanceMeters 0.0 must be finite and positive"))
        #expect(messages.contains("run.movingSeconds -5.0 must be finite and positive"))
    }

    @Test("Future-version fixture is rejected before field-level decoding")
    func futureVersionFixture() throws {
        let data = try fixtureData("conformance-future-version")
        #expect(throws: InterchangeCodec.CodecError.unsupportedSchemaVersion(99)) {
            try InterchangeCodec.decode(ExportBundle.self, from: data)
        }
    }

    @Test("Document envelopes round-trip and carry the schema version")
    func documentEnvelopes() throws {
        let exercise = ExerciseDTO(name: "Curl", muscleGroup: .biceps, exerciseType: .weightReps, equipment: [])
        let document = ExerciseDocument(exercise: exercise)
        let data = try InterchangeCodec.encode(document)
        let decoded = try InterchangeCodec.decode(ExerciseDocument.self, from: data)
        #expect(decoded == document)
        #expect(decoded.schemaVersion == 1)
    }
}
