import XCTest

/// An exercise added through the picker in a running workout, then the current exercise's last
/// set logged into the rest before the next: the exercise left, its rest, and the next exercise
/// stay on screen. The add's scroll to the list's end once left the list's position bound to that
/// end, and the room the rest puts under the list scrolled every row off the top. Three
/// exercises, so the end is out of view as the row goes in and the add scrolls; with two, it was
/// in view and nothing scrolled. Only the running app's scroll view shows where the list rests;
/// which set comes next and how long the rest is are `WorkoutLoggingTests`'. Its own test, since
/// it launches into a workout under way with a rest between exercises (`-seedWorkout 1`,
/// `-seedRest 30`, which overrides the launch's 0, the later value winning). In that rest it then
/// runs the count and its keys, the one UI check of a rest's countdown (`runRestKeys(in:)`).
///
/// `nonisolated` because XCTestCase's initializers are; the test drives the UI on the main actor.
final nonisolated class RestAfterAddUITests: XCTestCase {
    @MainActor
    func testRowsStayThroughARestAfterAnAdd() {
        let app = XCUIApplication()
        app.launchSeeding(
            ["biceps-curl", "goblet-squat", "dumbbell-row"],
            named: "Rest check",
            arguments: ["-seedSets", "2", "-seedWorkout", "1", "-seedRest", "30"],
        )
        let rows = app.exerciseRows
        let (left, next) = (rows.element(boundBy: 0), rows.element(boundBy: 1))
        XCTContext.runActivity(named: "After an add, a rest keeps the rows on screen") { _ in
            let before = left.frame.minY
            app.addExercise("Push-up", searching: "pushup")
            // The add scrolled toward the list's end, as the break needs.
            XCTAssertLessThan(
                reading(left.frame.minY, until: { $0 < before }, within: 2),
                before,
                "The add scrolled nothing: the end was in view",
            )
            app.tapWorkoutKey(reading: "Log set")
            XCTAssertEqual(
                reading(app.workoutKey.label, becoming: "Skip rest", within: 3),
                "Skip rest",
                "The last set of Biceps curl opened no rest",
            )
            XCTAssertTrue(
                settling(next.frame.minY, still: 0.25, within: 3),
                "Into the rest, the list never came to rest",
            )
            let bar = app.navigationBars.firstMatch.frame.maxY
            let key = app.workoutKey.frame.minY
            attach(named: "rest-after-add")
            XCTAssertGreaterThanOrEqual(
                left.frame.maxY,
                bar,
                "Biceps curl, the exercise left, went under the bar: \(left.frame)",
            )
            XCTAssertGreaterThanOrEqual(
                next.frame.minY,
                bar,
                "Goblet squat, the next exercise, went under the bar: \(next.frame)",
            )
            XCTAssertLessThanOrEqual(
                next.frame.maxY,
                key,
                "Goblet squat, the next exercise, is under the key: \(next.frame)",
            )
        }
        XCTContext
            .runActivity(named: "The rest counts down, +15 s lengthens it, Skip ends it") { _ in
                Self.runRestKeys(in: app)
            }
    }

    /// From the rest after the log, the count on the real clock and its keys' wire to it, which
    /// only the running app has: the countdown ticks, +15 s puts 15 s back on it, and Skip rest
    /// ends it on the next exercise's Log set. Their rules are `WorkoutRestTests`'.
    @MainActor
    private static func runRestKeys(in app: XCUIApplication) {
        let count = app.otherElements["Rest"]
        XCTAssertTrue(count.appears(), "The rest showed no countdown")
        let start = count.seconds
        XCTAssertLessThan(
            reading(count.seconds, until: { $0 < start }, within: 2),
            start,
            "The countdown stood still at \(start) s",
        )
        let ticked = count.seconds
        app.buttons["Plus 15 seconds"].tap()
        XCTAssertGreaterThan(
            reading(count.seconds, until: { $0 > ticked + 10 }, within: 2),
            ticked + 10,
            "+15 s left the countdown at \(count.seconds) s from \(ticked) s",
        )
        app.workoutKey.tap()
        XCTAssertTrue(count.disappears(), "The countdown stayed after Skip rest")
        // Goblet squat's "Start in" shows no key; Log set comes up after it.
        let logSet = app.buttons.matching(
            NSPredicate(format: "identifier == 'workout.key' AND label == 'Log set'"),
        ).firstMatch
        XCTAssertTrue(
            logSet.appears(within: XCUIApplication.startInWait),
            "Skip rest never brought back Log set",
        )
    }
}
