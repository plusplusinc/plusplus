import Testing
import Foundation
@testable import PlusPlusKit

@Suite("RoutineShareLink")
struct RoutineShareLinkTests {
    private func samplePayload() -> RoutineShareLink.Payload {
        let bench = ExerciseDTO(
            name: "Bench Press",
            muscleGroup: .chest,
            exerciseType: .weightReps,
            equipment: ["Barbell", "Bench"],
            notes: nil,
            videoURL: nil,
            isBuiltIn: true
        )
        let plank = ExerciseDTO(
            name: "Plank",
            muscleGroup: .core,
            exerciseType: .duration,
            equipment: [],
            notes: "Brace, don't sag.",
            videoURL: nil,
            isBuiltIn: true
        )
        let routine = RoutineDTO(
            name: "Push Day",
            restSeconds: 90,
            notes: "Tuesday & Friday",
            groups: [
                .init(sets: 3, exercises: [
                    .init(exercise: "Bench Press", weight: 135, reps: 8, repsUpper: 12, durationSeconds: nil)
                ]),
                .init(sets: 2, exercises: [
                    .init(exercise: "Plank", weight: nil, reps: nil, repsUpper: nil, durationSeconds: 60)
                ]),
            ]
        )
        return RoutineShareLink.Payload(routine: routine, exercises: [plank, bench], units: .lb)
    }

    @Test("Payload round-trips through the fragment exactly")
    func roundTrip() throws {
        let payload = samplePayload()
        let fragment = try RoutineShareLink.fragment(for: payload)
        let decoded = try RoutineShareLink.payload(fromFragment: fragment)
        #expect(decoded == payload)
    }

    @Test("Fragment is URL-safe: tagged, no padding, no +/ characters")
    func urlSafety() throws {
        let fragment = try RoutineShareLink.fragment(for: samplePayload())
        #expect(fragment.hasPrefix("0"))
        #expect(!fragment.contains("+"))
        #expect(!fragment.contains("/"))
        #expect(!fragment.contains("="))
    }

    @Test("Identical payloads produce identical links (deterministic)")
    func determinism() throws {
        let a = try RoutineShareLink.url(for: samplePayload()).absoluteString
        let b = try RoutineShareLink.url(for: samplePayload()).absoluteString
        #expect(a == b)
        #expect(a.hasPrefix("https://plusplus.fit/r#0"))
    }

    @Test("Exercise definitions sort by name regardless of input order")
    func exerciseOrdering() {
        let payload = samplePayload()
        #expect(payload.exercises.map(\.name) == ["Bench Press", "Plank"])
    }

    @Test("Both link forms decode: viewer https URL and app scheme")
    func bothLinkForms() throws {
        let payload = samplePayload()
        let https = try RoutineShareLink.url(for: payload)
        #expect(try RoutineShareLink.payload(from: https) == payload)

        let scheme = URL(string: "plusplus://r#" + (try RoutineShareLink.fragment(for: payload)))!
        #expect(RoutineShareLink.isShareLink(scheme))
        #expect(try RoutineShareLink.payload(from: scheme) == payload)
    }

    @Test("Errors: missing fragment, unknown tag, garbage, future version")
    func errors() throws {
        #expect(throws: RoutineShareLink.DecodeError.missingFragment) {
            try RoutineShareLink.payload(from: URL(string: "https://plusplus.fit/r")!)
        }
        #expect(throws: RoutineShareLink.DecodeError.unsupportedEncoding) {
            try RoutineShareLink.payload(fromFragment: "9abcdef")
        }
        #expect(throws: RoutineShareLink.DecodeError.undecodable) {
            try RoutineShareLink.payload(fromFragment: "0!!!not-base64!!!")
        }
        var future = samplePayload()
        future.share = 99
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let b64 = try encoder.encode(future).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        #expect(throws: RoutineShareLink.DecodeError.unsupportedVersion(99)) {
            try RoutineShareLink.payload(fromFragment: "0" + b64)
        }
    }

    @Test("A realistic 10-exercise routine stays comfortably link-sized")
    func sizeBound() throws {
        let exercises = (1...10).map { n in
            ExerciseDTO(
                name: "Exercise Number \(n)",
                muscleGroup: .back,
                exerciseType: .weightReps,
                equipment: ["Barbell", "Bench"],
                notes: "Some cue text for form goes here.",
                videoURL: nil,
                isBuiltIn: false
            )
        }
        let routine = RoutineDTO(
            name: "The Long One",
            restSeconds: 120,
            notes: nil,
            groups: exercises.map { dto in
                .init(sets: 3, exercises: [
                    .init(exercise: dto.name, weight: 185, reps: 8, repsUpper: 12, durationSeconds: nil)
                ])
            }
        )
        let url = try RoutineShareLink.url(for: RoutineShareLink.Payload(routine: routine, exercises: exercises))
        #expect(url.absoluteString.count < 8000)
    }
}
