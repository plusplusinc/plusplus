import XCTest

/// An exercise added through the picker in a running workout, then the current exercise's last
/// set logged into the rest before the next: the exercise left, its rest, and the next exercise
/// stay on screen. The add's scroll to the list's end once left the list's position bound to that
/// end, and the room the rest puts under the list scrolled every row off the top. Three
/// exercises, so the end is out of view as the row goes in and the add scrolls: with two, it
/// was in view and nothing scrolled. Only the
/// running app's scroll view shows where the list rests; which set comes next and how long the
/// rest is are `WorkoutLoggingTests`'. Its own test, since it launches into a workout under way
/// with a rest between exercises (`-seedWorkout 1`, `-seedRest 30`, after the launch's 0).
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
        XCTContext.runActivity(named: "After an add, a rest keeps the rows on screen") { _ in
            app.addExercise("Push-up", searching: "pushup")
            app.tapWorkoutKey(reading: "Log set")
            XCTAssertEqual(
                reading(app.workoutKey.label, becoming: "Skip rest", within: 3),
                "Skip rest",
                "The last set of Biceps curl opened no rest",
            )
            let rows = app.exerciseRows
            let (left, next) = (rows.element(boundBy: 0), rows.element(boundBy: 1))
            XCTAssertTrue(
                settling(next.frame.minY, still: 0.25, within: 3),
                "Into the rest, the list never came to rest",
            )
            let bar = app.navigationBars.firstMatch.frame.maxY
            let screen = app.windows.firstMatch.frame.maxY
            attach(named: "rest-after-add")
            XCTAssertGreaterThanOrEqual(
                left.frame.maxY,
                bar,
                "Biceps curl, the exercise left, went under the bar: \(left.frame)",
            )
            XCTAssertLessThanOrEqual(
                next.frame.maxY,
                screen,
                "Goblet squat, the next exercise, is off the screen: \(next.frame)",
            )
            XCTAssertGreaterThanOrEqual(
                next.frame.minY,
                bar,
                "Goblet squat, the next exercise, went under the bar: \(next.frame)",
            )
        }
    }
}
