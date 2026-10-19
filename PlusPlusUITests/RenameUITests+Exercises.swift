import XCTest

/// Adding, searching, and deleting exercises: adding within `testRenameAtDefaultSize`, so it
/// shares its launch, and deleting within `testDragAndDeleteRows`.
extension RenameUITests {
    /// The picker opens fast and without the keyboard, search narrows it, and a pick adds a row.
    @MainActor
    func addAndSearchExercises(in app: XCUIApplication, keyboard: XCUIElement) {
        let search = app.searchFields.firstMatch
        XCTContext.runActivity(named: "Add exercise opens the picker") { _ in
            XCTAssertFalse(app.buttons["Start"].exists, "Start shows with no exercises")
            _ = app.openPicker()
            XCTAssertFalse(keyboard.exists, "Search took focus when the picker opened")
            XCTAssertEqual(app.pickerRows.firstMatch.label, "Backward arm circles")
        }
        XCTContext.runActivity(named: "Search narrows and shows an empty state") { _ in
            search.tap()
            search.typeText("curl")
            let curls = ["Biceps curl, Dumbbells", "Hammer curl, Dumbbells"]
            XCTAssertTrue(app.pickerRows[curls[0]].appears())
            XCTAssertEqual(app.pickerRows.allElementsBoundByIndex.map(\.label), curls)
            app.searchForNothing(replacing: "curl", in: search)
            XCTAssertEqual(app.pickerRows.count, 0)
            attach(named: "picker-no-results")
            // While searching, the first Close ends the search; the next closes the sheet.
            for _ in 0 ..< 2 where search.exists {
                app.buttons["Close"].firstMatch.tap()
                _ = keyboard.disappears()
            }
            XCTAssertTrue(search.disappears(), "Close left the picker open")
            XCTAssertEqual(app.exerciseRows.count, 0, "Closing the picker added an exercise")
        }
        let exercises = XCUIApplication.nineExercises
        XCTContext.runActivity(named: "Start appears with the first exercise") { _ in
            app.addExercise(exercises[0].label)
            XCTAssertTrue(app.buttons["Start"].appears())
            app.buttons["Start"].tap()
            XCTAssertEqual(app.exerciseCount(becoming: 1), 1)
            XCTAssertFalse(search.exists, "Start opened something")
        }
        XCTContext.runActivity(named: "Six adds in a row, one a duplicate") { _ in
            for exercise in exercises[1 ... 6] {
                app.addExercise(exercise.label, searching: exercise.query)
            }
            XCTAssertEqual(app.exerciseCount(becoming: 7), 7)
            attach(named: "seven-exercises")
        }
        readRowsAtTheListEnd(in: app)
    }

    /// The rows read as name and plan, and at the end of the list both keys and the
    /// title stay reachable. Split from `addAndSearchExercises` so each body stays inside
    /// SwiftLint's length limit; the activities run in this order either way.
    @MainActor
    private func readRowsAtTheListEnd(in app: XCUIApplication) {
        XCTContext.runActivity(named: "Rows read as name and plan") { _ in
            let labels = app.exerciseRows.allElementsBoundByIndex.map(\.label)
            XCTAssertEqual(labels, [
                "Barbell bench press, 3 sets of 5 reps, 45 pounds",
                "Band pull-apart, 3 sets of 15 reps",
                "Band pull-apart, 3 sets of 15 reps",
                "Balance board hold, 3 sets of 30 seconds",
                "Barbell back squat, 3 sets of 5 reps, 45 pounds",
                "Biceps curl, 3 sets of 12 reps, 15 pounds per side",
                "Push-up, 3 sets of 10 reps",
            ])
        }
        XCTContext.runActivity(named: "An add that would hide Add exercise scrolls to it") { _ in
            // The eighth row still fits; the ninth pushes Add exercise below Start.
            for exercise in XCUIApplication.nineExercises[7...] {
                app.addExercise(exercise.label, searching: exercise.query)
            }
            XCTAssertTrue(app.addExerciseClearsStart(), "The add left Add exercise behind Start")
            attach(named: "nine-exercises")
        }
        XCTContext.runActivity(named: "A tap on the small title scrolls back to the top") { _ in
            app.scrollToTop(titled: "Arm and back day")
            let smallTitle = app.navigationBars.firstMatch.buttons["Arm and back day"]
            XCTAssertTrue(smallTitle.disappears(), "The small title stayed with the title in view")
        }
    }

    /// Start rides above the keyboard while the title is edited, rather than staying behind it,
    /// and goes back down with the keyboard when a tap just outside a two-line title ends the
    /// edit. A long press on the title shows the edit menu.
    @MainActor
    func startClearsKeyboard(in app: XCUIApplication, keyboard: XCUIElement) throws {
        let title = app.routineTitle
        let start = app.buttons["Start"]
        let atRest = start.frame
        let name = try XCTUnwrap(title.value as? String)
        let longer = name + " and core and arms"
        try XCTContext.runActivity(named: "Start rides above the keyboard") { _ in
            try title.tapToEditAtEnd(keyboard: keyboard)
            XCTAssertTrue(
                reading(start.frame.maxY <= keyboard.frame.minY, becoming: true, within: 2),
                "Start is behind the keyboard",
            )
            // Two lines, so the title is taller than its 44pt target.
            title.typeText(String(longer.dropFirst(name.count)))
            XCTAssertEqual(title.value(becoming: longer), longer)
            XCTAssertGreaterThan(title.frame.height, 44, "The longer name did not wrap")
        }
        XCTContext.runActivity(named: "A tap just below a two-line title ends the edit") { _ in
            // Outside the field, where SwiftUI still gives a tap to the target behind it, which
            // once started the edit again in the same tap and left Start behind the keyboard.
            title.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 1))
                .withOffset(CGVector(dx: 0, dy: 8)).tap()
            XCTAssertTrue(keyboard.disappears(), "The tap below the title kept the edit")
            XCTAssertEqual(
                reading(start.frame, becoming: atRest, within: 2),
                atRest,
                "Start did not go back down with the keyboard",
            )
            XCTAssertEqual(
                watchFrames(of: [start], for: Self.keyboardAvoidanceWindow),
                [atRest],
                "Start moved after the edit ended",
            )
        }
        XCTContext.runActivity(named: "A long press on the title shows the edit menu") { _ in
            title.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.25))
                .press(forDuration: 1)
            XCTAssertTrue(keyboard.appears(), "A long press did not start an edit")
            XCTAssertTrue(
                app.menuItems["Select All"].appears(),
                "A long press showed no edit menu",
            )
            title.typeText("\n")
            XCTAssertTrue(keyboard.disappears())
        }
        try XCTContext.runActivity(named: "The name goes back to one line") { _ in
            try title.tapToEditAtEnd(keyboard: keyboard)
            let delete = XCUIKeyboardKey.delete.rawValue
            title.typeText(String(repeating: delete, count: longer.count - name.count))
            XCTAssertEqual(title.value(becoming: name), name)
            title.typeText("\n")
            XCTAssertTrue(keyboard.disappears())
        }
    }

    /// The system's swipe actions: a swipe opens a row's Delete, a tap elsewhere closes it, a
    /// full swipe deletes outright, and with no rows left Start goes.
    @MainActor
    func deleteExercises(in app: XCUIApplication) {
        let delete = app.buttons["Delete"]
        XCTContext.runActivity(named: "A swipe opens a row, and Delete deletes it") { _ in
            // The superset checks leave the first two rows a pair.
            XCTAssertEqual(app.supersets, "AA.......")
            app.exerciseRows.element(boundBy: 1).swipeOpen()
            XCTAssertTrue(delete.appears(), "A swipe did not open the row")
            attach(named: "row-open")
            delete.tap()
            XCTAssertEqual(app.exerciseCount(becoming: 8), 8)
            XCTAssertTrue(delete.disappears())
            XCTAssertEqual(
                app.supersets(becoming: "........"),
                "........",
                "Deleting one of a pair left the other in a superset",
            )
        }
        XCTContext.runActivity(named: "A tap anywhere else closes an open row") { _ in
            let open = {
                app.exerciseRows.element(boundBy: 0).swipeOpen()
                XCTAssertTrue(delete.appears(), "A swipe did not open the row")
            }
            open()
            // Halfway between Add exercise and Start: clear of both keys' touch slop, and of
            // Start's bar, however many rows there are.
            let addExercise = app.buttons["Add exercise"]
            let gap = app.buttons["Start"].frame.minY - addExercise.frame.maxY
            addExercise.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1))
                .withOffset(CGVector(dx: 0, dy: gap / 2)).tap()
            XCTAssertTrue(delete.disappears(), "A tap on empty screen left the row open")
            open()
            app.buttons["Start"].tap()
            XCTAssertTrue(delete.disappears(), "A tap on Start left the row open")
            open()
            // The tap closes the row and still opens the picker.
            _ = app.openPicker()
            app.buttons["Close"].firstMatch.tap()
            XCTAssertTrue(app.searchFields.firstMatch.disappears())
            XCTAssertFalse(delete.exists, "Add exercise left the row open")
            let count = app.exerciseCount(becoming: 7, within: 1)
            XCTAssertEqual(count, 8, "A tap outside the row deleted it")
        }
        XCTContext.runActivity(named: "A full swipe deletes, and with no rows Start goes") { _ in
            for left in (0 ..< 8).reversed() {
                app.lastExerciseRow.fullSwipeLeft()
                XCTAssertEqual(
                    app.exerciseCount(becoming: left),
                    left,
                    "A full swipe did not delete",
                )
            }
            XCTAssertTrue(app.buttons["Start"].disappears(), "Start stayed with no exercises")
        }
    }
}

@MainActor
extension XCUIApplication {
    /// The rows `testRenameAtDefaultSize` adds, in order, each with the search that finds it
    /// when it is not in the picker's first screenful. Nine run past one screen.
    static let nineExercises: [(label: String, query: String?)] = [
        ("Barbell bench press, Barbell, bench", nil),
        ("Band pull-apart, Band", nil),
        ("Band pull-apart, Band", nil),
        ("Balance board hold, Balance board", nil),
        ("Barbell back squat, Barbell", nil),
        ("Biceps curl, Dumbbells", "biceps"),
        ("Push-up", "push-up"),
        ("Balance board hold, Balance board", nil),
        ("Barbell back squat, Barbell", nil),
    ]

    /// Launches into a new routine named `name` holding `nineExercises`, scrolled to its top,
    /// for the checks that only need the rows.
    func launchNineExercises(named name: String) {
        let title = launchNewRoutine()
        title.tap()
        XCTAssertTrue(keyboards.element.appears(), "A tap on the title did not start an edit")
        title.typeText(name + "\n")
        XCTAssertTrue(keyboards.element.disappears(), "Return did not end the edit")
        XCTAssertEqual(title.value(becoming: name), name)
        for exercise in Self.nineExercises {
            addExercise(exercise.label, searching: exercise.query)
        }
        XCTAssertTrue(addExerciseClearsStart(), "The add left Add exercise behind Start")
        scrollToTop(titled: name)
    }

    /// Taps through the keyboard's one-time tip on sliding to type, which a freshly erased
    /// simulator, as each Xcode Cloud run's is, shows over the keys a second or so after the
    /// keyboard first rises. It covers the keyboard's top, so a check of what shows there reads
    /// the tip. Its button is the app's, not the keyboard element's.
    func dismissKeyboardTip() {
        let tip = buttons["Continue"]
        if tip.exists {
            tip.tap()
            XCTAssertTrue(tip.disappears(), "The keyboard's tip stayed up")
        }
    }
}
