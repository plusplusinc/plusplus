import Foundation
import Testing
@testable import Session
@testable import WorkoutStore

/// Where a session built from the store's `Store.Launch` starts: the Workouts screen after a
/// finish, the workout otherwise. Which `Launch` the store finds is `StoreLaunchTests`'.
@Suite("Workout session launch")
struct AppSessionLaunchTests {
    private let store: Store
    private let saved = Workout(name: "Lower")

    init() async throws {
        let container = try WorkoutStoreContainer.make(
            mode: .inMemory,
            schema: Store.schema,
        )
        store = Store(modelContainer: container)
        try await store.save(saved, at: Date(timeIntervalSinceReferenceDate: 1))
    }

    private func session(_ launch: Store.Launch) -> AppSession {
        AppSession(
            launch: launch,
            store: store,
            namer: .muscleGroupsOnly,
            health: HealthSaving(client: .unavailable),
        )
    }

    @Test("After a finish it starts on the Workouts list, over a new workout, the drawer shut")
    func afterFinish() async {
        let session = session(.workouts)
        #expect(session.screen == .workouts)
        #expect(session.showing == .workouts)
        #expect(session.current.isEmpty)
        #expect(session.loggedWorkout == nil)
        #expect(!session.isDrawerOpen)
        await session.refreshRecent(weightUnit: .pounds)
        #expect(session.recent.map(\.id) == [saved.id])
    }

    @Test("From the list after a finish, the drawer marks Workouts")
    func afterFinishDrawer() {
        let session = session(.workouts)
        session.openDrawer()
        #expect(session.isDrawerOpen)
        #expect(session.drawerMark == nil)
        #expect(session.showing == .workouts)
    }

    @Test("From the list after a finish, + pushes a new workout and a row pushes its workout")
    func afterFinishList() async {
        let new = session(.workouts)
        await new.startNew()
        #expect(new.screen == .pushedWorkout)
        #expect(new.current.isEmpty)
        let opened = session(.workouts)
        await opened.open(saved.id, weightUnit: .pounds)
        #expect(opened.screen == .pushedWorkout)
        #expect(opened.current == saved)
    }

    @Test("Every other launch starts on its workout")
    func otherLaunches() {
        let logged = LoggedWorkout(workoutID: saved.id, workoutName: saved.name, startedAt: .now)
        let inProgress = session(.inProgress(saved, logged))
        #expect(inProgress.screen == .workout)
        #expect(inProgress.current == saved)
        #expect(inProgress.loggedWorkout == logged)
        let workout = session(.workout(saved))
        #expect(workout.screen == .workout)
        #expect(workout.current == saved)
        #expect(workout.loggedWorkout == nil)
        let new = session(.newWorkout)
        #expect(new.screen == .workout)
        #expect(new.current.isEmpty)
    }
}
