import XCTest

/// A workout across real taps and relaunches: Start growing the first exercise into the
/// current one with the next in view, tapping the key to log its sets until the next exercise
/// is current, the key going back to it once scrolled away, pause and resume,
/// edits staying on, the time and the next set held through a relaunch while paused, the drawer
/// locked, Finish offered, and Discard. Elapsed time, the time counted while the app was closed,
/// every saved field's round trip, the order of sets, the launch rule after Discard and Finish,
/// and the schema upgrade are unit-tested in the package, and `TitleWrappingUITests` relaunches a
/// running workout; this holds what only
/// the running app shows, with one relaunch, paused after the edits. Its own test, since it
/// launches with a workout's own setup.
///
/// `nonisolated` because XCTestCase's initializers are; the test drives the UI on the main actor.
final nonisolated class WorkoutUITests: XCTestCase {
    @MainActor
    func testWorkoutSurvivesRelaunch() throws {
        let app = XCUIApplication()
        // Long enough to scroll the current exercise out of view.
        let seeded = [
            "barbell-bench-press", "pull-up", "goblet-squat", "band-pull-apart",
            "balance-board-hold", "barbell-back-squat", "calf-raise", "step-up",
        ]
        let title = app.launchSeeding(seeded, arguments: ["-fallbackNames", "YES"])
        // Added through the picker, and Start pressed straight after, as the row still enters.
        app.pickExercise("Biceps curl, Dumbbells", searching: "biceps")
        startShowsTheCurrentExercise(in: app)
        tapsLogSets(in: app)
        theWayBackScrollsToIt(in: app)
        pauseAndResume(in: app)
        let renamed = try editsStayOn(in: app, title: title)
        XCTContext.runActivity(named: "The drawer is locked") { _ in
            XCTAssertFalse(app.buttons["Menu"].exists, "++ shows in a workout")
            app.edgeSwipe()
            XCTAssertFalse(app.drawerTitle.appears(within: 1), "The edge swipe opened the drawer")
        }
        // What launch opens after Discard is `RoutineStoreWorkoutTests`'.
        XCTContext
            .runActivity(named: "Finish is offered; Discard leaves the routine") { _ in
                app.discardWorkout(withSetsLogged: true)
                XCTAssertEqual(title.value as? String, renamed, "Discard opened another routine")
                XCTAssertFalse(app.endKey.exists)
                XCTAssertTrue(app.buttons["Menu"].exists, "No ++ after Discard")
            }
    }

    /// Start grows the first exercise to just under the bar, the next one in view under it, and
    /// puts End and the time key in the bar.
    @MainActor
    private func startShowsTheCurrentExercise(in app: XCUIApplication) {
        XCTContext.runActivity(named: "Start grows the first exercise into the current one") { _ in
            app.buttons["Start"].tap()
            // Pressed as the last row added still enters, Start's room under the list once
            // scrolled the list into it, out of sight, and the scroll back undid the landing.
            XCTAssertFalse(
                reading(app.exerciseRows.firstMatch.frame.maxY <= 0, until: { $0 }, within: 0.6),
                "Start scrolled the first exercise out of sight",
            )
            XCTAssertTrue(app.workoutTime.appears(), "Start began no workout")
            XCTAssertEqual(app.workoutTime.label, "Pause")
            XCTAssertTrue(app.endKey.exists)
            XCTAssertTrue(app.buttons["Start"].disappears(), "Start stayed in a workout")
            XCTAssertFalse(app.buttons["Menu"].exists, "++ stayed in a workout")
            let rows = app.exerciseRows
            let (current, next) = (rows.element(boundBy: 0), rows.element(boundBy: 1))
            XCTAssertTrue(
                current.label.hasPrefix("Barbell bench press, Set 1 of 3"),
                "The first exercise isn't the current one: \(current.label)",
            )
            let screen = app.windows.firstMatch.frame
            let laidOut = reading(next.frame.maxY <= screen.maxY, becoming: true, within: 3)
            XCTAssertTrue(laidOut, "The next exercise is not in view under the current one")
            XCTAssertGreaterThanOrEqual(
                current.frame.minY,
                app.navigationBars.firstMatch.frame.maxY - 1,
                "The current exercise is under the bar",
            )
            attach(named: "workout-started")
            current.swipeOpen()
            XCTAssertFalse(app.buttons["Delete"].appears(within: 1), "The current row swiped")
        }
    }

    /// Three taps on the key on Barbell bench press: one moves it to its second set, the third
    /// on to Pull-up, which lands under the bar, the key reading Log set throughout. Which set
    /// comes next, and the key's words, are `WorkoutLoggingTests`'; this is the tap's wire from
    /// the bar to the log and the row, and the landing after a move.
    @MainActor
    private func tapsLogSets(in app: XCUIApplication) {
        XCTContext.runActivity(named: "A tap on the key logs a set, and the last one moves on") { _ in
            let rows = app.exerciseRows
            let bench = rows.element(boundBy: 0)
            app.tapWorkoutKey(reading: "Log set")
            XCTAssertTrue(
                reading(
                    bench.label,
                    until: { $0.hasPrefix("Barbell bench press, Set 2 of 3") },
                    within: 3,
                )
                .hasPrefix("Barbell bench press, Set 2 of 3"),
                "A tap logged nothing: \(bench.label)",
            )
            XCTAssertEqual(app.workoutKey.label, "Log set", "The key changed on a log")
            app.tapWorkoutKey(reading: "Log set")
            XCTAssertTrue(
                reading(bench.label, until: { $0.contains("Set 3 of 3") }, within: 3)
                    .contains("Set 3 of 3"),
                "The second tap logged nothing: \(bench.label)",
            )
            app.tapWorkoutKey(reading: "Log set")
            let pullUp = rows.element(boundBy: 1)
            XCTAssertTrue(
                reading(pullUp.label, until: { $0.hasPrefix("Pull-up, Set 1 of 3") }, within: 3)
                    .hasPrefix("Pull-up, Set 1 of 3"),
                "The last set did not move on to Pull-up: \(pullUp.label)",
            )
            let bar = app.navigationBars.firstMatch.frame.maxY
            let top = reading(pullUp.frame.minY, until: { abs($0 - bar) < 30 }, within: 3)
            XCTAssertLessThan(abs(top - bar), 30, "Pull-up did not land under the bar: \(top)")
            attach(named: "workout-moved-on")
        }
    }

    /// Scrolled away from the current exercise, the key goes back to it, logging nothing, and
    /// reads Log set again, which then logs.
    @MainActor
    private func theWayBackScrollsToIt(in app: XCUIApplication) {
        XCTContext.runActivity(named: "Scrolled away, the key goes back to the current one") { _ in
            let key = app.workoutKey
            let current = app.exerciseRows.element(boundBy: 1)
            let before = current.label
            let wayBack = "Go to current exercise, Pull-up"
            for _ in 0 ..< 3 where !key.label.hasPrefix(wayBack) {
                app.swipeUp()
                _ = reading(key.label, until: { $0.hasPrefix(wayBack) }, within: 1.5)
            }
            attach(named: "workout-scrolled-away")
            app.tapWorkoutKey(reading: wayBack)
            // Read once the scroll back has landed.
            let bar = app.navigationBars.firstMatch.frame.maxY
            XCTAssertGreaterThanOrEqual(
                reading(current.frame.minY, until: { $0 >= bar - 1 }, within: 2),
                bar - 1,
                "The way back left the current exercise under the bar",
            )
            XCTAssertEqual(current.label, before, "The way back logged a set")
            app.tapWorkoutKey(reading: "Log set")
            XCTAssertTrue(
                reading(current.label, until: { $0.hasPrefix("Pull-up, Set 2 of 3") }, within: 3)
                    .hasPrefix("Pull-up, Set 2 of 3"),
                "Back on Pull-up, a tap logged nothing: \(current.label)",
            )
        }
    }

    /// Paused, the time holds and the key reads Resume; resumed, it carries on.
    @MainActor
    private func pauseAndResume(in app: XCUIApplication) {
        XCTContext.runActivity(named: "Pause holds the time; resume carries on") { _ in
            let key = app.workoutTime
            key.tap()
            XCTAssertEqual(reading(key.label, becoming: "Resume", within: 2), "Resume")
            let held = key.seconds
            attach(named: "workout-paused")
            // Waited out in full when it holds. The time reads in whole seconds, so a second and
            // a half sees a tick if one comes.
            XCTAssertEqual(reading(key.seconds, until: { $0 != held }, within: 1.5), held)
            key.tap()
            XCTAssertEqual(reading(key.label, becoming: "Pause", within: 2), "Pause")
            // Returns at the first tick, so a longer window costs nothing when the time runs.
            XCTAssertGreaterThan(reading(key.seconds, until: { $0 > held }, within: 2.5), held)
        }
    }

    /// An add, a delete, and a rename each change the routine mid-workout, and, paused, the
    /// workout comes back through a relaunch with them and its time held. Returns the new name.
    @MainActor
    private func editsStayOn(in app: XCUIApplication, title: XCUIElement) throws -> String {
        try XCTContext
            .runActivity(named: "Edits stay on, and paused, a relaunch keeps the time") { _ in
                app.addExercise("Push-up", searching: "push-up")
                app.exerciseRows.element(boundBy: 2).fullSwipeLeft()
                XCTAssertEqual(app.exerciseCount(becoming: 9), 9, "The swipe deleted nothing")
                moveARow(in: app)
                let name = try XCTUnwrap(title.value as? String)
                app.scrollToTop(titled: name)
                let keyboard = app.keyboards.element
                try title.tapToEditAtEnd(keyboard: keyboard)
                title.typeText(" day\n")
                let renamed = name + " day"
                XCTAssertEqual(title.value(becoming: renamed), renamed)
                XCTAssertTrue(keyboard.disappears())
                let key = app.workoutTime
                key.tap()
                XCTAssertEqual(reading(key.label, becoming: "Resume", within: 2), "Resume")
                let held = key.seconds
                app.relaunch()
                XCTAssertTrue(key.appears(), "The workout did not come back")
                XCTAssertEqual(key.label, "Resume")
                XCTAssertEqual(key.seconds, held)
                key.tap()
                XCTAssertEqual(reading(key.label, becoming: "Pause", within: 2), "Pause")
                XCTAssertEqual(title.value as? String, renamed)
                XCTAssertTrue(
                    app.exerciseRows.element(boundBy: 1).label.hasPrefix("Pull-up, Set 2 of 3"),
                    "The relaunch did not come back on Pull-up's second set",
                )
                XCTAssertEqual(app.workoutKey.label, "Log set", "The key after a relaunch")
                XCTAssertEqual(app.exerciseNames, [
                    "Barbell bench press", "Pull-up", "Band pull-apart", "Barbell back squat",
                    "Balance board hold", "Calf raise", "Step-up", "Biceps curl", "Push-up",
                ])
                return renamed
            }
    }

    /// Holding a row below the current exercise and dragging it past the next one moves it,
    /// as it does outside a workout.
    @MainActor
    private func moveARow(in app: XCUIApplication) {
        let rows = app.exerciseRows
        let (moved, below) = (rows.element(boundBy: 3), rows.element(boundBy: 4))
        for _ in 0 ..< 3 where !(moved.isHittable && below.isHittable) {
            app.swipeUp()
        }
        var expected = app.exerciseNames
        let height = below.frame.minY - moved.frame.minY
        // Past the halfway point of the row below it.
        moved.center.holdAndDrag(to: moved.center.down(1.2 * height))
        expected.swapAt(3, 4)
        XCTAssertEqual(
            reading(app.exerciseNames, becoming: expected, within: 2),
            expected,
            "The drag moved nothing in a workout",
        )
    }
}

extension XCUIElement {
    /// The time key's value, "1 minute, 5 seconds", in seconds.
    @MainActor
    var seconds: Int {
        let spoken = value as? String ?? ""
        return spoken.split(separator: ", ").reduce(0) { total, part in
            let words = part.split(separator: " ")
            guard let count = words.first.flatMap({ Int($0) }), let unit = words.last else {
                return total
            }
            let scale = unit.hasPrefix("hour") ? 3600 : unit.hasPrefix("minute") ? 60 : 1
            return total + count * scale
        }
    }
}
