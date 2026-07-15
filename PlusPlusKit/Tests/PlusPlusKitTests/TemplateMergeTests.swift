import Foundation
import Testing
import PlusPlusKit

@Suite("TemplateMerge")
struct TemplateMergeTests {
    private let path = "program/routines/push-day.json"

    private func routine(rest: Int, notes: String?, groupSets: Int) throws -> Data {
        let dto = RoutineDTO(
            name: "Push Day", restSeconds: rest, notes: notes,
            groups: [.init(sets: groupSets, exercises: [.init(exercise: "Bench Press", reps: 5)])]
        )
        return try InterchangeCodec.encode(RoutineDocument(routine: dto))
    }

    private func decoded(_ data: Data) throws -> RoutineDTO {
        try InterchangeCodec.decode(RoutineDocument.self, from: data).routine
    }

    @Test("Disjoint field edits both apply — no conflict")
    func disjointEditsMerge() throws {
        let base = try routine(rest: 90, notes: "old", groupSets: 3)
        let local = try routine(rest: 120, notes: "old", groupSets: 3)   // changed rest
        let remote = try routine(rest: 90, notes: "new", groupSets: 3)   // changed notes

        let merged = try #require(TemplateMerge.merge(base: base, local: local, remote: remote, path: path))
        let dto = try decoded(merged)
        #expect(dto.restSeconds == 120)   // local's edit
        #expect(dto.notes == "new")       // remote's edit
    }

    @Test("A same-field collision resolves local-wins")
    func sameFieldLocalWins() throws {
        let base = try routine(rest: 90, notes: "old", groupSets: 3)
        let local = try routine(rest: 90, notes: "mine", groupSets: 3)
        let remote = try routine(rest: 90, notes: "theirs", groupSets: 3)

        let merged = try #require(TemplateMerge.merge(base: base, local: local, remote: remote, path: path))
        #expect(try decoded(merged).notes == "mine")
    }

    @Test("A structural (groups) edit on one side is taken")
    func structuralFieldFromOneSide() throws {
        let base = try routine(rest: 90, notes: "n", groupSets: 3)
        let local = try routine(rest: 90, notes: "n", groupSets: 3)     // unchanged
        let remote = try routine(rest: 90, notes: "n", groupSets: 5)    // changed the group

        let merged = try #require(TemplateMerge.merge(base: base, local: local, remote: remote, path: path))
        #expect(try decoded(merged).groups.first?.sets == 5)   // remote's structural edit
    }

    @Test("Output is canonical — a no-net-change merge round-trips to local bytes")
    func canonicalOutput() throws {
        // Both sides made the SAME edit: merge must equal that canonical form.
        let base = try routine(rest: 90, notes: "old", groupSets: 3)
        let edited = try routine(rest: 100, notes: "old", groupSets: 3)
        let merged = try #require(TemplateMerge.merge(base: base, local: edited, remote: edited, path: path))
        #expect(merged == edited)
    }

    @Test("transitionSeconds merges as its own field (#369)")
    func transitionFieldMerges() throws {
        func routine(transition: Int?) throws -> Data {
            let dto = RoutineDTO(
                name: "Push Day", restSeconds: 90, transitionSeconds: transition, notes: "n",
                groups: [.init(sets: 3, exercises: [.init(exercise: "Bench Press", reps: 5)])]
            )
            return try InterchangeCodec.encode(RoutineDocument(routine: dto))
        }
        // The phone set a transition; the repo copy predates the field —
        // the local edit applies without touching anything else.
        let merged = try #require(TemplateMerge.merge(
            base: try routine(transition: nil),
            local: try routine(transition: 10),
            remote: try routine(transition: nil),
            path: path
        ))
        #expect(try decoded(merged).transitionSeconds == 10)
        #expect(try decoded(merged).restSeconds == 90)
    }

    @Test("Non-template paths and undecodable input return nil")
    func rejectsNonTemplates() throws {
        let valid = try routine(rest: 90, notes: "n", groupSets: 3)
        #expect(TemplateMerge.merge(base: valid, local: valid, remote: valid, path: "history/2026/x.json") == nil)
        let junk = Data("not json".utf8)
        #expect(TemplateMerge.merge(base: nil, local: junk, remote: junk, path: path) == nil)
    }
}
