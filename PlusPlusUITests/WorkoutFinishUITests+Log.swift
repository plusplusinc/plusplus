import XCTest

/// The finished workout after a relaunch, run last within `testFinishKeyKeepsTheWorkout`:
/// launch opens a new workout, and Log lists the finished one. What Log reads from the store
/// and how each row reads are the package's (`StoreLoggedWorkoutTests`, `WorkoutLogTextTests`);
/// this is what a relaunch brings back to Log, and the system push and back of an opened
/// workout.
@MainActor
extension WorkoutFinishUITests {
    func relaunchKeepsIt(named name: String, title: XCUIElement, in app: XCUIApplication) {
        XCTContext.runActivity(named: "The logged one was kept: launch opens a new workout") { _ in
            app.relaunch()
            XCTAssertFalse(app.workoutTime.exists, "The finished workout came back running")
            XCTAssertNotEqual(
                title.value as? String,
                name,
                "Launch reopened the workout, as after a discard",
            )
        }
        XCTContext.runActivity(named: "Log lists it after the relaunch, and opens it") { _ in
            app.openDrawer(andTap: "Log")
            let logged = app.buttons.matching(identifier: "log.workout").firstMatch
            XCTAssertTrue(logged.appears(), "Log lists no finished workout")
            XCTAssertTrue(logged.label.hasPrefix(name), "Log's row reads \(logged.label)")
            logged.tap()
            // A row is one element, read as its sentence, which starts with its name.
            let plank = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", "Plank"))
                .firstMatch
            XCTAssertTrue(plank.appears(), "The opened workout shows no Plank")
            app.tapBack()
            XCTAssertTrue(logged.appears(), "Back did not return to History")
        }
    }
}
