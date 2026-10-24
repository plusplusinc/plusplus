import XCTest

/// Saving and the launch rule across real quits and relaunches. The store, each field's round
/// trip, the launch rule, and the names are unit-tested in the package; this holds the wire
/// from the screen to the store, with two relaunches: one that brings back every saved field at
/// once (rows in their new order, their duplicates and values, the generated name, a superset
/// and its shared rounds), and one that shows a routine cleared to nothing is gone. Names come from
/// the muscle
/// groups (`-fallbackNames`), so the same name shows on any simulator. The title's color, white
/// for a name whether typed or generated and gray for New routine, is read from pixels against
/// the placeholder's own gray at the start.
///
/// `nonisolated` because XCTestCase's initializers are; the test drives the UI on the main actor.
final nonisolated class RoutineAutosaveUITests: XCTestCase {
    private static let bench = "Barbell bench press, Barbell, bench"
    private static let pullUp = "Pull-up, Pull-up bar"
    private static let gobletSquat = "Goblet squat, Kettlebell"

    @MainActor
    func testRoutineSurvivesRelaunch() throws {
        let app = XCUIApplication()
        let title = app.launchNewRoutine(arguments: ["-fallbackNames", "YES"])
        XCTAssertEqual(title.value as? String, "New routine")
        let gray = try Ink.ofTitle(in: title.frame).contrast

        nameFollowsTheExercises(in: app, title: title, gray: gray)
        valuesChangeInTheSheet(in: app)
        moveARow(in: app)
        joinASuperset(in: app)
        XCTContext.runActivity(
            named: "Rows, order, the generated name, and a superset survive a relaunch",
        ) { _ in
            app.relaunch()
            XCTAssertEqual(title.value as? String, "Chest and back")
            // Moved, joined, and with the rounds the sheet gave both; the second pull-up keeps
            // the reps its sheet gave it, and the first its own.
            XCTAssertEqual(app.exerciseRows.allElementsBoundByIndex.map(\.label), Self.joined)
            XCTAssertEqual(app.supersets, "AA.")
            XCTAssertTrue(title.inkIsWhite(against: gray), "The generated name came back gray")
            attach(named: "after-relaunch")
        }
        try typedNameStays(in: app, title: title, gray: gray)
        try clearedRoutineIsGone(in: app, title: title, gray: gray)
        drawerSwitchesRoutines(in: app, title: title)
    }

    /// An unnamed routine is named for its exercises as they come and go, in white.
    @MainActor
    private func nameFollowsTheExercises(in app: XCUIApplication, title: XCUIElement, gray: Int) {
        XCTContext.runActivity(named: "An unnamed routine is named for its exercises") { _ in
            app.addExercise(Self.bench)
            XCTAssertEqual(title.value(becoming: "Chest"), "Chest")
            app.addExercise(Self.pullUp, searching: "pull-up")
            XCTAssertEqual(title.value(becoming: "Chest and back"), "Chest and back")
            app.addExercise(Self.pullUp, searching: "pull-up")
            app.addExercise(Self.gobletSquat, searching: "goblet")
            XCTAssertEqual(title.value(becoming: "Full body"), "Full body")
            XCTAssertTrue(title.inkIsWhite(against: gray), "The generated name is not white")
            attach(named: "generated-name")
        }
        XCTContext.runActivity(named: "A deleted exercise leaves the name") { _ in
            app.lastExerciseRow.fullSwipeLeft()
            XCTAssertEqual(app.exerciseCount(becoming: 3), 3)
            XCTAssertEqual(title.value(becoming: "Chest and back"), "Chest and back")
        }
    }

    /// A row's sheet steps its values, and the row reads the result; its twin keeps its own.
    @MainActor
    private func valuesChangeInTheSheet(in app: XCUIApplication) {
        XCTContext.runActivity(named: "A row's sheet changes only that row's values") { _ in
            app.exerciseRows.element(boundBy: 2).tap()
            let reps = app.buttons["Reps"]
            XCTAssertTrue(reps.appears(), "Tapping a row opened no sheet")
            XCTAssertEqual(reps.value as? String, "6 reps")
            reps.tap()
            let increase = app.buttons["Increase"]
            XCTAssertTrue(increase.appears(), "Tapping Reps opened no stepper")
            increase.tapAtCenter()
            increase.tapAtCenter()
            XCTAssertEqual(reps.value(becoming: "8 reps"), "8 reps")
            attach(named: "sheet-stepped")
            app.buttons["Close"].tap()
            XCTAssertTrue(reps.disappears(), "Close left the sheet up")
            XCTAssertEqual(
                app.exerciseRows.allElementsBoundByIndex.map(\.label),
                [
                    "Barbell bench press, 3 sets of 5 reps, 45 pounds",
                    "Pull-up, 3 sets of 6 reps",
                    "Pull-up, 3 sets of 8 reps",
                ],
            )
        }
    }

    /// The last row dragged above the first moves there.
    @MainActor
    private func moveARow(in app: XCUIApplication) {
        XCTContext.runActivity(named: "A held row moves to a new place") { _ in
            let rows = app.exerciseRows
            let (first, last) = (rows.element(boundBy: 0), rows.element(boundBy: 2))
            // Above the first row's middle, so its gap opens above the first row.
            last.center.holdAndDrag(to: first.center.down(-0.2 * first.frame.height))
            let moved = ["Pull-up", "Barbell bench press", "Pull-up"]
            XCTAssertEqual(reading(app.exerciseNames, becoming: moved, within: 2), moved)
        }
    }

    /// The rows after `moveARow` and `joinASuperset`: the first two a superset with 4 rounds.
    private static let joined = [
        "Pull-up, 4 sets of 8 reps",
        "Barbell bench press, 4 sets of 5 reps, 45 pounds",
        "Pull-up, 3 sets of 6 reps",
    ]

    /// Two rows joined by a node share their rounds, which a member's sheet says and steps for
    /// both.
    @MainActor
    private func joinASuperset(in app: XCUIApplication) {
        XCTContext.runActivity(named: "A superset's rounds are shared in its sheet") { _ in
            let rows = app.exerciseRows
            rows.element(boundBy: 0).nodePoint.holdAndDrag(to: rows.element(boundBy: 1).nodePoint)
            XCTAssertEqual(app.supersets(becoming: "AA."), "AA.")
            rows.element(boundBy: 1).tap()
            let rounds = app.buttons["Rounds, Shared with Pull-up"]
            XCTAssertTrue(rounds.appears(), "A member's sheet doesn't say its rounds are shared")
            rounds.tap()
            app.buttons["Increase"].tapAtCenter()
            XCTAssertEqual(rounds.value(becoming: "4"), "4")
            attach(named: "sheet-shared-rounds")
            app.buttons["Close"].tap()
            XCTAssertTrue(rounds.disappears(), "Close left the sheet up")
            let labels = { app.exerciseRows.allElementsBoundByIndex.map(\.label) }
            XCTAssertEqual(reading(labels(), becoming: Self.joined, within: 2), Self.joined)
        }
    }

    /// Editing opens on the generated name; replaced, the typed name stays as exercises change.
    @MainActor
    private func typedNameStays(in app: XCUIApplication, title: XCUIElement, gray: Int) throws {
        try XCTContext.runActivity(named: "A typed name stays as exercises change") { _ in
            let keyboard = app.keyboards.element
            try title.tapToEditAtEnd(keyboard: keyboard)
            XCTAssertEqual(title.value(becoming: "Chest and back"), "Chest and back")
            let delete = XCUIKeyboardKey.delete.rawValue
            title.typeText(String(repeating: delete, count: "Chest and back".count) + "Push pull\n")
            XCTAssertTrue(keyboard.disappears(), "Return should end editing")
            XCTAssertEqual(title.value(becoming: "Push pull"), "Push pull")
            app.addExercise(Self.gobletSquat, searching: "goblet")
            // The name comes with the row, so it would already have changed.
            XCTAssertEqual(title.value as? String, "Push pull")
            XCTAssertTrue(title.inkIsWhite(against: gray), "The typed name is not white")
            attach(named: "typed-name")
        }
    }

    /// Every row deleted and the name cleared is nothing, which is not kept.
    @MainActor
    private func clearedRoutineIsGone(
        in app: XCUIApplication,
        title: XCUIElement,
        gray: Int,
    ) throws {
        try XCTContext.runActivity(named: "A routine cleared to nothing is gone") { _ in
            for left in (0 ..< 4).reversed() {
                app.lastExerciseRow.fullSwipeLeft()
                XCTAssertEqual(app.exerciseCount(becoming: left), left)
            }
            XCTAssertTrue(app.buttons["Start"].disappears())
            let keyboard = app.keyboards.element
            try title.tapToEditAtEnd(keyboard: keyboard)
            // Deleting from the end, not ⌘A, which has hidden the keyboard on Xcode Cloud.
            let delete = XCUIKeyboardKey.delete.rawValue
            title.typeText(String(repeating: delete, count: "Push pull".count) + "\n")
            XCTAssertTrue(keyboard.disappears())
            XCTAssertEqual(title.value(becoming: "New routine"), "New routine")
            XCTAssertFalse(title.inkIsWhite(against: gray), "New routine is not gray")
            attach(named: "cleared")
            app.relaunch()
            XCTAssertEqual(title.value as? String, "New routine")
            XCTAssertEqual(app.exerciseRows.count, 0)
        }
    }
}

@MainActor
extension XCUIElement {
    /// Whether the title's strongest ink is a name's, well past the placeholder's `gray`, once
    /// a name has typed in or the placeholder has crossfaded back. After two seconds, whatever
    /// it last was.
    func inkIsWhite(against gray: Int) -> Bool {
        let frame = frame
        return reading(
            ((try? Ink.ofTitle(in: frame).contrast) ?? 0) > gray * 5 / 4,
            becoming: true,
            within: 2,
        )
    }
}
