import XCTest

/// A workout across real taps and relaunches: Start growing the first exercise into the
/// current one with the next in view, the way back to it, pause and resume, the time counting
/// the time away, edits staying on, the time held while paused, the drawer locked, and Discard.
/// Elapsed time, every saved field's round trip, the launch rule after Discard and Finish, which
/// needs a set done, and the schema upgrade are unit-tested in the package; this holds what
/// only the running app shows, with two relaunches: running, and paused after the edits. Its
/// own test, since it launches with a workout's own setup.
///
/// `nonisolated` because XCTestCase's initializers are; the test drives the UI on the main actor.
final nonisolated class WorkoutUITests: XCTestCase {
    @MainActor
    func testWorkoutSurvivesRelaunch() throws {
        let app = XCUIApplication()
        // Long enough to scroll the current exercise out of view.
        let seeded = [
            "barbell-bench-press", "pull-up", "goblet-squat", "band-pull-apart",
            "balance-board-hold", "barbell-back-squat",
        ]
        let title = app.launchSeeding(seeded, arguments: ["-fallbackNames", "YES"])
        // Added through the picker, and Start pressed straight after, as the row still enters.
        app.pickExercise("Biceps curl, Dumbbells", searching: "biceps")
        startShowsTheCurrentExercise(in: app)
        theWayBackScrollsToIt(in: app)
        pauseAndResume(in: app)
        survivesRelaunch(in: app)
        let renamed = try editsStayOn(in: app, title: title)
        XCTContext.runActivity(named: "The drawer is locked") { _ in
            XCTAssertFalse(app.buttons["Menu"].exists, "++ shows in a workout")
            app.edgeSwipe()
            XCTAssertFalse(app.drawerTitle.appears(within: 1), "The edge swipe opened the drawer")
        }
        // What launch opens after Discard is `RoutineStoreWorkoutTests`'.
        XCTContext.runActivity(named: "Discard leaves the routine as it was") { _ in
            app.discardWorkout()
            XCTAssertEqual(title.value as? String, renamed, "Discard opened another routine")
            XCTAssertTrue(app.buttons["Start"].appears(), "The workout came back")
            XCTAssertFalse(app.endKey.exists)
            XCTAssertTrue(app.buttons["Menu"].exists, "No ++ after Discard")
        }
    }

    /// Start grows the first exercise to just under the bar, the next one in view under it and
    /// the one after off the screen, and puts End and the time key in the bar.
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
            let (current, next, after) = (
                rows.element(boundBy: 0), rows.element(boundBy: 1), rows.element(boundBy: 2),
            )
            XCTAssertTrue(
                current.label.hasPrefix("Barbell bench press, Set 1 of 3"),
                "The first exercise isn't the current one: \(current.label)",
            )
            let screen = app.windows.firstMatch.frame
            let laidOut = reading(
                next.frame.maxY <= screen.maxY && after.frame.minY >= screen.maxY - 1,
                becoming: true,
                within: 3,
            )
            XCTAssertTrue(laidOut, "Not just the current and next exercises in view")
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

    /// Scrolled away from the current exercise, a floating key goes back to it and then goes.
    @MainActor
    private func theWayBackScrollsToIt(in app: XCUIApplication) {
        XCTContext.runActivity(named: "Scrolled away, a key goes back to the current one") { _ in
            let way = app.buttons["workout.current"]
            for _ in 0 ..< 3 where !way.exists {
                app.swipeUp()
            }
            XCTAssertTrue(way.appears(), "No way back once scrolled away")
            attach(named: "workout-scrolled-away")
            way.tap()
            XCTAssertTrue(way.disappears(), "The way back stayed once back")
            let current = app.exerciseRows.firstMatch
            // Read once the scroll back has landed.
            let bar = app.navigationBars.firstMatch.frame.maxY
            XCTAssertGreaterThanOrEqual(
                reading(current.frame.minY, until: { $0 >= bar - 1 }, within: 2),
                bar - 1,
                "The way back left the current exercise under the bar",
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

    /// After a relaunch the workout is back on its current exercise, its time counting the
    /// time away. Paused, the time held is `editsStayOn`'s relaunch.
    @MainActor
    private func survivesRelaunch(in app: XCUIApplication) {
        let key = app.workoutTime
        XCTContext.runActivity(named: "Running, a relaunch counts the time away") { _ in
            let before = key.seconds
            let quit = Date.now
            app.relaunch()
            XCTAssertTrue(key.appears(), "The workout did not come back")
            let away = Int(Date.now.timeIntervalSince(quit))
            XCTAssertGreaterThanOrEqual(key.seconds, before + away - 1)
            XCTAssertEqual(key.label, "Pause")
            XCTAssertFalse(app.buttons["Start"].exists)
            XCTAssertTrue(app.exerciseRows.firstMatch.label.contains("Set 1 of 3"))
            attach(named: "workout-relaunched")
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
                XCTAssertEqual(app.exerciseCount(becoming: 7), 7, "The swipe deleted nothing")
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
                XCTAssertEqual(app.exerciseNames, [
                    "Barbell bench press", "Pull-up", "Band pull-apart", "Barbell back squat",
                    "Balance board hold", "Biceps curl", "Push-up",
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
