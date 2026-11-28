import XCTest

/// After the last planned set, the key at the bottom reads Finish workout and finishes with no
/// "End this workout?" dialog, going to Log by the drawer, where the workout comes into
/// History; and keeps it: a relaunch then opens the Workouts list, where after Discard it
/// reopens this one (`StoreWorkoutSessionTests` holds both launch rules and every saved field).
/// Which set comes next is `WorkoutLoggingTests`', and how the row looks is
/// `WorkoutRailSnapshotTests`'; this is the key's wire to finishing and to Log. On
/// the way, it reads where Start leaves the list, which only the running app's scroll view
/// shows: on a one-exercise workout, a break left it low in most runs; that a tap beside the
/// low + through "Start in" opens nothing, which only the running app's hit testing shows; and
/// that the exercise,
/// held until it lifts and let go in place, stays there. Its own test, since it
/// launches with one exercise seeded and its own name. The exercise is a plank of one 8 s set
/// (`-seedSets 1`, `-seedTime 8`), which counts down after its "Start in" and logs itself, with
/// no tap on its key: long enough for the drag to finish inside the count, never across its
/// log. Only the running app has the count's watch on the real clock and its wire to
/// the log, whose rules `TimedSetTests` holds. That one log reaches the workout's end; logs
/// that stay on an exercise, tapped, are `LiveWorkoutUITests`'.
///
/// `nonisolated` because XCTestCase's initializers are; the test drives the UI on the main actor.
final nonisolated class WorkoutFinishUITests: XCTestCase {
    /// One set of 8 s.
    /// With a Health never asked, so the finish brings Log's prompt to sync to it.
    private static let oneTimedSet = [
        "-seedSets", "1", "-seedTime", "8", "-seedHealth", "notAsked",
    ]

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
            // Through the set's "Start in" there is no key, its room kept, and the + sits low in
            // it: a tap in that room beside the +, below the one row, opened Add exercise as a
            // tap below the last row does. Taken inside the wait for the key, so it costs
            // nothing more.
            XCTAssertFalse(app.workoutKey.exists, "A key showed through \"Start in\"")
            let plus = app.buttons["Add exercise"].frame
            app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: plus.minX / 2, dy: plus.midY)).tap()
            XCTAssertTrue(
                app.searchButton.staysAway(),
                "A tap beside the + through \"Start in\" opened Add exercise",
            )
            // Read once the workout's key is up, after the set's "Start in", which shows none: a
            // bottom inset that changed at the key's hand-off left this workout's list 52.7 pt
            // low in most runs.
            XCTAssertTrue(
                app.workoutKey.appears(within: XCUIApplication.startInWait),
                "The workout's key never came up",
            )
            XCTAssertEqual(app.workoutKey.label, "Log early", "The counting set's key")
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
            // What is left of its 8 s count, then the log's beats, with no tap.
            XCTAssertEqual(
                reading(app.workoutKey.label, becoming: "Finish workout", within: 11),
                "Finish workout",
                "The key did not turn to Finish workout after the last set",
            )
            XCTAssertTrue(
                app.buttons["Add exercise"].exists,
                "Add exercise went with the last set",
            )
        }
        keyFinishGoesToLog(named: name, in: app)
        relaunchKeepsIt(named: name, title: title, in: app)
    }
}
