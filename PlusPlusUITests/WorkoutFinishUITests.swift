import XCTest

/// After the last planned set, the key at the bottom reads Finish workout and finishes at once,
/// with no "End this workout?" dialog, and keeps the workout: a relaunch then opens a new
/// routine, where after Discard it reopens this one (`RoutineStoreWorkoutTests` holds both
/// launch rules and every saved field). Which set comes next is `WorkoutLoggingTests`', and
/// how the row looks is `WorkoutRailSnapshotTests`'; this is the key's wire to finishing, which
/// nothing in the app shows afterward, so a break that discarded the sets would go unseen. On
/// the way, it reads where Start leaves the list, which only the running app's scroll view
/// shows: on a one-exercise routine, a break left it low in most runs. Its own test, since it
/// launches with one exercise seeded and its own name.
///
/// `nonisolated` because XCTestCase's initializers are; the test drives the UI on the main actor.
final nonisolated class WorkoutFinishUITests: XCTestCase {
    @MainActor
    func testFinishKeyKeepsTheWorkout() {
        let app = XCUIApplication()
        let name = "Finish check"
        let title = app.launchSeeding(["push-up"], named: name)
        let row = app.exerciseRows.element(boundBy: 0)
        XCTContext.runActivity(named: "Start leaves the list resting on the exercise") { _ in
            app.buttons["Start"].tap()
            XCTAssertTrue(app.workoutTime.appears(), "Start began no workout")
            // Read once the workout's key is up, past Start's hand-off to it: a bottom inset that
            // changed there left this routine's list 52.7 pt low in most runs.
            XCTAssertEqual(
                reading(app.workoutKey.label, becoming: "Log set", within: 3),
                "Log set",
                "The workout's key never came up",
            )
            // The key comes up near the end of the grow's spring (`RoutineScreen.keyReturnDelay`,
            // `growBeat`), so the row may still be moving: read where it rests once it holds
            // still, not within a clock's window, which one slow accessibility query can use up
            // (a slow Xcode Cloud run read it 9.7 pt low).
            XCTAssertTrue(row.settles(within: 3), "After Start, the list never came to rest")
            let bar = app.navigationBars.firstMatch.frame.maxY
            let top = row.frame.minY
            XCTAssertLessThan(abs(top - bar), 1, "After Start, the list rests \(top - bar) pt low")
        }
        XCTContext.runActivity(named: "Logging the last set turns the key to Finish workout") { _ in
            for set in 1 ... 3 {
                app.tapWorkoutKey(reading: set < 3 ? "Log set" : "Log last set")
                if set < 3 {
                    let next = "Push-up, Set \(set + 1) of 3"
                    XCTAssertTrue(
                        reading(row.label, until: { $0.hasPrefix(next) }, within: 3)
                            .hasPrefix(next),
                        "Set \(set) did not log: \(row.label)",
                    )
                }
            }
            XCTAssertEqual(
                reading(app.workoutKey.label, becoming: "Finish workout", within: 3),
                "Finish workout",
                "The key did not turn to Finish workout after the last set",
            )
            XCTAssertTrue(
                app.buttons["Add exercise"].exists,
                "The list does not end in Add exercise",
            )
        }
        XCTContext.runActivity(named: "Finish workout ends at once, with no dialog") { _ in
            app.tapWorkoutKey(reading: "Finish workout")
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
