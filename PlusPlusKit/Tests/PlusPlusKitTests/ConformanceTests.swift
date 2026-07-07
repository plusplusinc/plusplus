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
        #expect(bundle.exercises.map(\.name) == ["Band Pulses", "Plank Hold"])
        #expect(bundle.routines.first?.groups.count == 2)
        #expect(bundle.sessions.first?.sets.count == 2)
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
        let messages = InterchangeValidator.validate(bundle).map(\.message).joined(separator: "; ")

        #expect(messages.contains("duplicate exercise name"))
        #expect(messages.contains("restSeconds 5 outside 15...600"))
        #expect(messages.contains("sets 0 outside 1...20"))
        #expect(messages.contains("unresolved exercise reference"))
        #expect(messages.contains("repsUpper 15 must exceed reps 20"))
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
