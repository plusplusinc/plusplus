import Foundation
import Testing
import PlusPlusKit

@Suite("SyncPlanner")
struct SyncPlannerTests {
    private let path = "program/workouts/push-day.json"
    private let a = Data("a".utf8)
    private let b = Data("b".utf8)
    private let c = Data("c".utf8)

    @Test("First sync pushes everything local")
    func firstSync() {
        let plan = SyncPlanner.plan(local: [path: a], remote: [:], base: [:])
        #expect(plan.writes == [FileWrite(path: path, data: a)])
        #expect(plan.pulls.isEmpty && plan.conflicts.isEmpty)
    }

    @Test("Identical content is unchanged")
    func unchanged() {
        let plan = SyncPlanner.plan(local: [path: a], remote: [path: a], base: [path: a])
        #expect(plan.unchanged == [path])
        #expect(plan.writes.isEmpty && plan.pulls.isEmpty && plan.conflicts.isEmpty)
    }

    @Test("Local edit with untouched remote wins")
    func localEdit() {
        let plan = SyncPlanner.plan(local: [path: b], remote: [path: a], base: [path: a])
        #expect(plan.writes == [FileWrite(path: path, data: b)])
    }

    @Test("Remote edit with untouched local is pulled")
    func remoteEdit() {
        let plan = SyncPlanner.plan(local: [path: a], remote: [path: b], base: [path: a])
        #expect(plan.pulls == [path])
        #expect(plan.writes.isEmpty)
    }

    @Test("Divergent edits are a conflict, not a clobber")
    func conflict() {
        let plan = SyncPlanner.plan(local: [path: b], remote: [path: c], base: [path: a])
        #expect(plan.conflicts == [path])
        #expect(plan.writes.isEmpty && plan.pulls.isEmpty)
    }

    @Test("Remote-only files are adopted, never deleted")
    func remoteOnly() {
        let other = "program/exercises/band-pulses.json"
        let plan = SyncPlanner.plan(local: [path: a], remote: [path: a, other: b], base: [path: a])
        #expect(plan.pulls == [other])
        #expect(plan.unchanged == [path])
    }

    @Test("Convergent identical edits need no action even with stale base")
    func convergent() {
        let plan = SyncPlanner.plan(local: [path: b], remote: [path: b], base: [path: a])
        #expect(plan.unchanged == [path])
        #expect(plan.conflicts.isEmpty)
    }
}
