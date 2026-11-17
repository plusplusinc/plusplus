import XCTest

/// Saving across a real quit and relaunch. The store, each field's round trip, the launch rule,
/// a routine cleared to nothing deleted, and the names are unit-tested in the package; this
/// holds the wire from the screen to the store, with one relaunch that brings back every saved
/// field at once (rows in their new order, their duplicates and values, a superset and its
/// shared rounds, an exercise created from the picker, and a name typed with no Return). Names come
/// from the muscle
/// groups (`-fallbackNames`), so the same name shows on any simulator. The
/// title's color, white for a name whether typed or generated and gray for New routine, is read
/// from pixels against the placeholder's own gray at the start. The drawer over saved routines is
/// `RoutineDrawerUITests`'.
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
        // Typed first, so the row edits after it, each saved as made, are what the quit keeps,
        // and not a save the name's last key made of the whole routine.
        try nameStillBeingTyped(in: app, title: title)
        valuesChangeInTheSheet(in: app)
        moveARow(in: app)
        joinASuperset(in: app)
        createAnExercise(in: app)
        XCTContext.runActivity(
            named: "Rows, order, a superset, a created exercise, and a typed name survive a quit",
        ) { _ in
            app.relaunch()
            XCTAssertEqual(title.value(becoming: "Push pull"), "Push pull")
            // Moved, joined, and with the rounds the sheet gave both; the second pull-up keeps
            // the reps its sheet gave it, and the first its own.
            XCTAssertEqual(app.exerciseRowLabels, Self.joined + [Self.ringRow])
            XCTAssertEqual(app.supersets, "AA..")
            attach(named: "after-relaunch")
        }
        XCTContext.runActivity(named: "A typed name stays as exercises change") { _ in
            // The created exercise, back in the picker's list with its equipment after the
            // relaunch.
            app.addExercise("Ring row with rotation, Rings", searching: "ring row")
            // The name comes with the row, so it would already have changed.
            XCTAssertEqual(title.value as? String, "Push pull")
            XCTAssertTrue(title.inkIsWhite(against: gray), "The typed name is not white")
            attach(named: "typed-name")
        }
        try clearedRoutineIsNewRoutine(in: app, title: title, gray: gray)
    }

    /// An unnamed routine is named for its exercises as they come and go, in white.
    @MainActor
    private func nameFollowsTheExercises(in app: XCUIApplication, title: XCUIElement, gray: Int) {
        XCTContext.runActivity(named: "An unnamed routine is named for its exercises") { _ in
            app.addExercise(Self.bench)
            XCTAssertEqual(title.value(becoming: "Chest"), "Chest")
            app.addExercise(Self.pullUp, searching: "pullup")
            XCTAssertEqual(title.value(becoming: "Chest and back"), "Chest and back")
            app.addExercise(Self.pullUp, searching: "pullup")
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
                app.exerciseRowLabels,
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
            XCTAssertEqual(
                reading(app.exerciseRowLabels, becoming: Self.joined, within: 2),
                Self.joined,
            )
        }
    }

    /// Editing opens on the generated name; replaced, the typed name is kept without Return
    /// through Home and back, and the edit is left open for the next tap on a row to end. That
    /// each key reaches the routine with no edit ended is `RoutineDrawerUITests`' chevron check
    /// and `EditableTitleTypingTests`'; a generated name is made again from the exercises, never
    /// stored (`RoutineNamerTests`).
    @MainActor
    private func nameStillBeingTyped(in app: XCUIApplication, title: XCUIElement) throws {
        let keyboard = app.keyboards.element
        try XCTContext.runActivity(named: "A name still being typed is kept through Home") { _ in
            try title.typeOver("Chest and back", with: "Push pul", keyboard: keyboard)
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertTrue(keyboard.appears(), "Back from Home, the title isn't being edited")
            XCTAssertEqual(title.value(becoming: "Push pul"), "Push pul")
            attach(named: "still-editing-after-home")
            title.typeText("l")
            // Typing can return before the app has handled the key.
            XCTAssertEqual(title.value(becoming: "Push pull"), "Push pull")
        }
    }

    /// Every row deleted and the name cleared is nothing, the gray New routine. That the store
    /// deletes it is `RoutineStoreTests`': a relaunch can't show it, since a routine cleared and
    /// kept would open as the same empty New routine.
    @MainActor
    private func clearedRoutineIsNewRoutine(
        in app: XCUIApplication,
        title: XCUIElement,
        gray: Int,
    ) throws {
        try XCTContext.runActivity(named: "A routine cleared to nothing is New routine") { _ in
            let plus = app.buttons["Add exercise"]
            let aboveStart = plus.frame
            for left in (0 ..< 5).reversed() {
                app.lastExerciseRow.fullSwipeLeft()
                XCTAssertEqual(app.exerciseCount(becoming: left), left)
            }
            XCTAssertTrue(app.buttons["Start"].disappears())
            // The last row's swipe takes the + down with Start and brings the empty line back.
            XCTAssertTrue(app.noExercises.appears(), "No exercises did not return")
            XCTAssertTrue(plus.settles(), "The + kept moving")
            XCTAssertGreaterThan(plus.frame.minY, aboveStart.minY, "The + stayed up with no Start")
            let keyboard = app.keyboards.element
            try title.typeOver("Push pull", with: "\n", keyboard: keyboard)
            XCTAssertTrue(keyboard.disappears())
            XCTAssertEqual(title.value(becoming: "New routine"), "New routine")
            XCTAssertTrue(title.inkIsGray(against: gray), "New routine is not gray")
            attach(named: "cleared")
        }
    }
}

@MainActor
extension XCUIElement {
    /// Whether the title's strongest ink is a name's, well past the placeholder's `gray`, once
    /// a name has typed in. After two seconds, whatever it last was.
    func inkIsWhite(against gray: Int) -> Bool {
        let frame = frame
        return reading(Self.isWhite(in: frame, against: gray), becoming: true, within: 2)
    }

    /// Whether the title's strongest ink is no brighter than a placeholder's, once it has
    /// crossfaded back to it. Waiting for white not to come would spend the whole timeout.
    func inkIsGray(against gray: Int) -> Bool {
        let frame = frame
        return !reading(Self.isWhite(in: frame, against: gray), becoming: false, within: 2)
    }

    private static func isWhite(in frame: CGRect, against gray: Int) -> Bool {
        ((try? Ink.ofTitle(in: frame).contrast) ?? 0) > gray * 5 / 4
    }
}
