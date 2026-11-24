import XCTest

/// After the last planned set, the key at the bottom reads Finish workout and finishes with no
/// "End this workout?" dialog, going to Log by the drawer, where the workout comes into
/// History; and keeps it: a relaunch then opens the Workouts list, where after Discard it
/// reopens this one (`StoreLoggedWorkoutTests` holds both launch rules and every saved field).
/// Which set comes next is `WorkoutLoggingTests`', and how the row looks is
/// `WorkoutRailSnapshotTests`'; this is the key's wire to finishing and to Log. On
/// the way, it reads where Start leaves the list, which only the running app's scroll view
/// shows: on a one-exercise workout, a break left it low in most runs; and that the exercise,
/// held until it lifts and let go in place, stays there. Its own test, since it
/// launches with one exercise seeded and its own name. The exercise is a plank of one 3 s set
/// (`-seedSets 1`, `-seedTime 3`), which counts down and logs itself after "Start now", with no
/// tap on its key: only the running app has the count's watch on the real clock and its wire to
/// the log, whose rules `TimedSetTests` holds. That one log reaches the workout's end; logs
/// that stay on an exercise, tapped, are `LiveWorkoutUITests`'.
///
/// `nonisolated` because XCTestCase's initializers are; the test drives the UI on the main actor.
final nonisolated class WorkoutFinishUITests: XCTestCase {
    /// One set of 3 s.
    private static let oneTimedSet = ["-seedSets", "1", "-seedTime", "3"]

    @MainActor
    func testFinishKeyKeepsTheWorkout() {
        let app = XCUIApplication()
        let name = "Finish check"
        let title = app.launchSeeding(["plank"], named: name, arguments: Self.oneTimedSet)
        let row = app.exerciseRows.element(boundBy: 0)
        // The bar's ••• gives its place to the workout's time (and takes it back after,
        // `LiveWorkoutUITests`): the bar draws its items itself, so only the running app shows
        // which one is there.
        let more = app.buttons["workout.more"]
        XCTContext.runActivity(named: "Start leaves the list resting on the exercise") { _ in
            app.buttons["Start"].tap()
            XCTAssertTrue(app.workoutTime.appears(), "Start began no workout")
            XCTAssertTrue(more.disappears(), "••• stayed in the bar during a workout")
            // Read once the workout's key is up, past Start's hand-off to it: a bottom inset that
            // changed there left this workout's list 52.7 pt low in most runs.
            XCTAssertEqual(
                reading(app.workoutKey.label, becoming: "Start now", within: 3),
                "Start now",
                "The workout's key never came up",
            )
            // The key comes up near the end of the grow's spring (`WorkoutScreen.keyReturnDelay`,
            // `growBeat`), so read where the row rests once its top holds still, not within a
            // clock's window: on a slow runner one accessibility query can outlast the window.
            XCTAssertTrue(
                settling(row.frame.minY, still: 0.25, within: 3),
                "After Start, the list never came to rest",
            )
            let bar = app.navigationBars.firstMatch.frame.maxY
            let low = row.frame.minY - bar - XCUIApplication.currentLabelDrop
            XCTAssertLessThan(abs(low), 1, "After Start, the list rests \(low) pt low")
        }
        // Which slot a drop lands in is `RailDragTests`'; this is the scroll view's range across
        // the drop, which only the running app shows: on this list, shorter than the screen, the
        // room a held row adds below it once left it shorter than the screen for a pass on the
        // drop, and the list jumped to its top. Read against where the row was, not the bar, so
        // it holds wherever Start left it.
        XCTContext.runActivity(named: "Held and let go in place, the exercise stays put") { _ in
            let before = row.frame.minY
            row.center.holdAndDrag(to: row.center)
            XCTAssertTrue(
                settling(row.frame.minY, still: 0.25, within: 3),
                "After the drop, the list never came to rest",
            )
            let moved = row.frame.minY - before
            XCTAssertLessThan(abs(moved), 1, "After the drop, the exercise moved \(moved) pt")
        }
        XCTContext.runActivity(named: "A timed set counts down and logs itself, to Finish") { _ in
            app.tapWorkoutKey(reading: "Start now")
            // Its 3 s count, then the log's beats, with no tap.
            XCTAssertEqual(
                reading(app.workoutKey.label, becoming: "Finish workout", within: 6),
                "Finish workout",
                "The key did not turn to Finish workout after the last set",
            )
            XCTAssertTrue(
                app.buttons["Add exercise"].exists,
                "Add exercise went with the last set",
            )
        }
        // When each beat comes is `AppSessionDrawerWayTests`', and Log's leaving the workout out
        // until it comes in is `LogPeriodTests`'; this is the key's wire through the session to
        // the drawer and Log, which only the running app composes.
        XCTContext.runActivity(named: "Finish workout goes to Log by the drawer, no dialog") { _ in
            app.tapWorkoutKey(reading: "Finish workout")
            XCTAssertFalse(app.buttons["Discard workout"].exists, "Finish workout asked first")
            // The "++" and the rest after it, then the drawer, with no tap.
            XCTAssertTrue(app.drawerTitle.appears(within: 4), "The drawer never opened")
            XCTAssertTrue(app.drawerTitle.disappears(within: 4), "The drawer never closed")
            let tabs = app.segmentedControls.firstMatch.buttons
            XCTAssertTrue(tabs["History"].isSelected, "Log is not on History")
            XCTAssertTrue(app.buttons["Menu"].exists, "Log shows no ++, as if pushed")
            // The first workout ever: History's one row takes the empty line's place.
            let logged = app.buttons.matching(identifier: "log.workout").firstMatch
            XCTAssertTrue(logged.appears(), "The finished workout never came into History")
            XCTAssertTrue(logged.label.hasPrefix(name), "History's row reads \(logged.label)")
            XCTAssertFalse(app.buttons["log.goToWorkouts"].exists, "Go to Workouts stayed")
            XCTAssertFalse(app.endKey.exists, "End stayed after Finish workout")
        }
        relaunchKeepsIt(named: name, title: title, in: app)
    }
}
