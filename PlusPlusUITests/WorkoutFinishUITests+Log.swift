import XCTest

/// The finished workout after a relaunch, run last within `testFinishKeyKeepsTheWorkout`:
/// launch opens the Workouts list, and Log lists the finished one. Which launch the store finds
/// is `StoreLaunchTests`'; what Log reads from the store and how each row reads are the
/// package's (`StoreLoggedWorkoutTests`, `WorkoutLogTextTests`);
/// this is what a relaunch brings back to Log, the system push and back of an opened
/// workout, the segmented control's wire from each tab to what it shows, and a row's swipe to
/// Delete, which ends it on an empty History.
@MainActor
extension WorkoutFinishUITests {
    func relaunchKeepsIt(named name: String, title: XCUIElement, in app: XCUIApplication) {
        XCTContext.runActivity(named: "The logged one was kept: launch opens Workouts") { _ in
            // Fails on a relaunch that doesn't list the workout on Workouts.
            app.relaunch(landingOn: app.listedWorkout(named: name))
            XCTAssertFalse(app.workoutTime.exists, "The finished workout came back running")
            XCTAssertFalse(title.exists, "Launch opened a workout, not the list")
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
        // The system's segmented control is composed in the app, and only there does a tab
        // reach what the store holds: `WorkoutDiffTests` and `WorkoutBalanceTests` hold what each
        // tab works out, `LogSnapshotTests` how its rows look, and `LogPeriodTests` the period.
        XCTContext
            .runActivity(named: "History, Diff, Balance: each tab shows the one workout") { _ in
                let tabs = app.segmentedControls.firstMatch.buttons
                XCTAssertEqual(
                    tabs.allElementsBoundByIndex.map(\.label),
                    ["History", "Diff", "Balance"],
                )
                XCTAssertTrue(tabs["History"].isSelected, "Log is not on History")
                // The period shows once, in the bar, read as words.
                let period = app.navigationBars.staticTexts
                    .matching(NSPredicate(format: "label CONTAINS %@", " to "))
                XCTAssertEqual(period.count, 1, "The bar reads no period, or more than one")
                // Log slides back in under the popped workout.
                XCTAssertTrue(tabs["Diff"].settles(), "Diff kept moving")
                tabs["Diff"].tap()
                // One workout is no change yet: Diff is its one line.
                let line = app
                    .staticTexts["An exercise shows here once it has been done in two workouts."]
                XCTAssertTrue(line.appears(), "Diff shows no line about two workouts")
                XCTAssertFalse(
                    app.buttons["log.workout"].exists,
                    "Diff still lists History's workouts",
                )
                tabs["Balance"].tap()
                // The plank's one set is the only one: Core has it, the other five have none.
                let groups = app.descendants(matching: .any)
                    .matching(NSPredicate(
                        format: "label ENDSWITH %@ OR label ENDSWITH %@",
                        " sets",
                        " set",
                    ))
                XCTAssertTrue(groups["Core, 1 set"].appears(), "Balance counts no set for Core")
                XCTAssertEqual(groups.count, 6, "Balance shows \(groups.count) muscle groups")
                XCTAssertFalse(line.exists, "Balance still shows Diff's line")
            }
        deleteFromHistory(named: name, in: app)
    }

    /// The system's swipe actions and alert, composed on History's scroll view, show only in the
    /// running app; what the delete stores and what the log reads after it are
    /// `AppSessionLogDeleteTests`' and `StoreDeleteTests`'.
    private func deleteFromHistory(named name: String, in app: XCUIApplication) {
        XCTContext
            .runActivity(named: "A History row's swipe asks first, and Delete takes it out") { _ in
                app.segmentedControls.firstMatch.buttons["History"].tap()
                let logged = app.buttons.matching(identifier: "log.workout").firstMatch
                XCTAssertTrue(logged.appears(), "History lists no finished workout")
                logged.swipeOpen()
                let delete = app.buttons["Delete"]
                XCTAssertTrue(delete.appears(), "A swipe did not open the row")
                delete.tap()
                let message = app.answerAlert("Delete from Log?", with: "Delete")
                XCTAssertTrue(message.hasPrefix("\(name), "), "The alert's line reads \(message)")
                XCTAssertTrue(logged.disappears(), "Delete left the row in History")
                XCTAssertTrue(
                    app.buttons["log.goToWorkouts"].appears(),
                    "History without its one workout shows no Go to Workouts",
                )
            }
    }
}
