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
        dialogFinishGoesToLog(named: name, in: app)
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

    /// Run last, from the empty History the delete leaves. That a finish goes to Log by the
    /// drawer and that a started workout is at the root are `AppSessionDrawerWayTests`' and
    /// `AppSessionScreenTests`'; this is the wire from the system dialog's Finish workout, which
    /// only the running app composes, to the same finish as the key's, on a workout opened from
    /// the Workouts list.
    func dialogFinishGoesToLog(named name: String, in app: XCUIApplication) {
        XCTContext
            .runActivity(named: "End's Finish, on a workout from the list, goes to Log") { _ in
                let goToWorkouts = app.buttons["log.goToWorkouts"]
                XCTAssertTrue(goToWorkouts.settles(), "Go to Workouts kept moving")
                goToWorkouts.tap()
                let listed = app.listedWorkout(named: name)
                XCTAssertTrue(listed.appears(within: 5), "Go to Workouts showed no list")
                // The list comes in under the closing drawer.
                XCTAssertTrue(app.drawerTitle.disappears(within: 4), "The drawer stayed open")
                XCTAssertTrue(listed.settles(), "The list kept moving")
                listed.tap()
                let start = app.buttons["Start"]
                XCTAssertTrue(start.appears(), "The row opened no workout")
                XCTAssertTrue(app.buttons["BackButton"].exists, "The workout isn't pushed")
                // The workout slides in as it is pushed.
                XCTAssertTrue(start.settles(), "Start kept moving")
                start.tap()
                app.tapWorkoutKey(reading: "Start now")
                // The dialog offers Finish only once a set is logged: the 3 s count, with no tap.
                XCTAssertEqual(
                    reading(app.workoutKey.label, becoming: "Finish workout", within: 6),
                    "Finish workout",
                    "The timed set never logged itself",
                )
                app.openEndDialog(withSetsLogged: true)
                let finish = app.buttons
                    .matching(NSPredicate(
                        format: "label == %@ AND identifier != %@",
                        "Finish workout",
                        "workout.key",
                    ))
                    .firstMatch
                XCTAssertTrue(finish.settles(), "The dialog kept moving")
                finish.tap()
                // The "++" and the rest after it, then the drawer, with no tap.
                XCTAssertTrue(app.drawerTitle.appears(within: 4), "The drawer never opened")
                XCTAssertTrue(app.drawerTitle.disappears(within: 4), "The drawer never closed")
                let logged = app.buttons.matching(identifier: "log.workout").firstMatch
                XCTAssertTrue(logged.appears(), "The finished workout never came into History")
                XCTAssertTrue(logged.label.hasPrefix(name), "History's row reads \(logged.label)")
                XCTAssertTrue(app.buttons["Menu"].exists, "Log shows no ++")
                XCTAssertFalse(app.buttons["BackButton"].exists, "Log shows a back button")
            }
    }
}
