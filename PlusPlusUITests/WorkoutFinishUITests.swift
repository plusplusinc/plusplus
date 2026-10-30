import XCTest

/// After the last planned set, the Finish workout key under the last exercise finishes at once,
/// with no "End this workout?" dialog, and keeps the workout: a relaunch then opens a new
/// routine, where after Discard it reopens this one (`RoutineStoreWorkoutTests` holds both
/// launch rules and every saved field). Which set comes next is `WorkoutLoggingTests`', and
/// how the row looks is `WorkoutRailSnapshotTests`'; this is the key's wire to finishing, which
/// nothing in the app shows afterward, so a break that discarded the sets would go unseen. Its
/// own test, since it launches with one exercise seeded and its own name.
///
/// `nonisolated` because XCTestCase's initializers are; the test drives the UI on the main actor.
final nonisolated class WorkoutFinishUITests: XCTestCase {
    @MainActor
    func testFinishKeyKeepsTheWorkout() {
        let app = XCUIApplication()
        let name = "Finish check"
        let title = app.launchSeeding(["push-up"], named: name)
        XCTContext.runActivity(named: "Logging the last set shows Finish workout") { _ in
            app.buttons["Start"].tap()
            XCTAssertTrue(app.workoutTime.appears(), "Start began no workout")
            let finish = app.buttons["workout.finish"]
            XCTAssertFalse(finish.exists, "Finish workout showed before the last set")
            let row = app.exerciseRows.element(boundBy: 0)
            for set in 1 ... 3 {
                XCTAssertFalse(finish.exists, "Finish workout showed before set \(set)")
                app.slideToLog(on: row)
                if set < 3 {
                    let next = "Push-up, Set \(set + 1) of 3"
                    XCTAssertTrue(
                        reading(row.label, until: { $0.hasPrefix(next) }, within: 3)
                            .hasPrefix(next),
                        "Set \(set) did not log: \(row.label)",
                    )
                }
            }
            XCTAssertTrue(finish.appears(), "No Finish workout after the last set")
        }
        XCTContext.runActivity(named: "Finish workout ends at once, with no dialog") { _ in
            app.buttons["workout.finish"].tap()
            XCTAssertTrue(app.buttons["Start"].appears(), "Finish workout left the workout running")
            XCTAssertFalse(app.buttons["Discard workout"].exists, "Finish workout asked first")
            XCTAssertFalse(app.endKey.exists, "End stayed after Finish workout")
        }
        XCTContext.runActivity(named: "The workout was kept: launch opens a new routine") { _ in
            app.relaunch()
            XCTAssertFalse(app.workoutTime.exists, "The finished workout came back running")
            XCTAssertNotEqual(
                title.value as? String,
                name,
                "Launch reopened the routine, as after a discard",
            )
        }
    }
}
