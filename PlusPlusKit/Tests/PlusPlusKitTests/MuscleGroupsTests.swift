import Foundation
import Testing
@testable import PlusPlusKit

@Suite("MuscleGroups")
struct MuscleGroupsTests {
    @Test("Normalization keeps the primary first and drops repeats")
    func normalizes() {
        #expect(MuscleGroups.normalized(primary: .chest, others: [.triceps, .shoulders])
            == [.chest, .triceps, .shoulders])
        // The primary wins its place even when it also appears in `others`.
        #expect(MuscleGroups.normalized(primary: .chest, others: [.triceps, .chest, .triceps])
            == [.chest, .triceps])
        #expect(MuscleGroups.normalized(primary: .core, others: []) == [.core])
    }

    @Test("A list normalizes against its own head, falling back when empty")
    func normalizesList() {
        #expect(MuscleGroups.normalized([.back, .biceps, .back], fallback: .chest) == [.back, .biceps])
        #expect(MuscleGroups.normalized([], fallback: .chest) == [.chest])
    }

    @Test("Encoding round-trips, and a single group still encodes")
    func codec() {
        let groups: [MuscleGroup] = [.chest, .triceps, .shoulders]
        #expect(MuscleGroups.decode(MuscleGroups.encode(groups)) == groups)
        // A one-group list is meaningful storage (a pruned built-in), not
        // noise: it must survive the round trip rather than collapsing to
        // "no explicit list".
        #expect(MuscleGroups.decode(MuscleGroups.encode([.chest])) == [.chest])
        #expect(MuscleGroups.encode([]) == nil)
        #expect(MuscleGroups.decode(nil) == nil)
    }

    @Test("Garbage and unknown group names decode to nil, never a crash")
    func decodeTolerance() {
        #expect(MuscleGroups.decode(Data("not json".utf8)) == nil)
        let unknownOnly = try? JSONEncoder().encode(["forearms"])
        #expect(MuscleGroups.decode(unknownOnly) == nil)
        // A partially-unknown list keeps what it recognizes rather than
        // dropping the exercise's whole classification.
        let mixed = try? JSONEncoder().encode(["chest", "forearms", "triceps"])
        #expect(MuscleGroups.decode(mixed) == [.chest, .triceps])
    }
}
