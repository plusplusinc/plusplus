import XCTest

/// Adding exercises, within `testRenameAtDefaultSize`, so it shares its launch. Deleting is
/// `RowDragUITests`'.
extension RenameUITests {
    /// The picker opens fast and without the keyboard, and a pick adds a row. The rest of the
    /// rows are seeded by a relaunch, and one more is added through the picker's search onto
    /// them. Search's list and empty state are left to use, and the add's scroll to Add exercise
    /// is `TitleWrappingUITests`' at AX5.
    @MainActor
    func addExercises(in app: XCUIApplication, keyboard: XCUIElement) {
        let search = app.searchFields.firstMatch
        XCTContext.runActivity(named: "Add exercise opens the picker") { _ in
            XCTAssertFalse(app.buttons["Start"].exists, "Start shows with no exercises")
            _ = app.openPicker()
            XCTAssertFalse(keyboard.exists, "Search took focus when the picker opened")
            XCTAssertEqual(app.pickerRows.firstMatch.label, "Backward arm circles")
        }
        let (seeded, added) = XCUIApplication.renameRows
        XCTContext.runActivity(named: "Start appears with the first exercise") { _ in
            app.pickerRows[seeded[0].label].tap()
            XCTAssertTrue(search.disappears(), "The add left the picker open")
            XCTAssertEqual(app.exerciseCount(becoming: 1), 1, "The pick added no row")
            // What Start does is `WorkoutUITests`'.
            XCTAssertTrue(app.buttons["Start"].appears())
        }
        XCTContext.runActivity(named: "An add through search lands after seeded rows") { _ in
            app.launchSeeding(seeded.map(\.id), named: "Arm and back day")
            app.addExercise(added.label, searching: added.query)
            attach(named: "nine-exercises")
        }
        XCTContext.runActivity(named: "Rows read as name and plan") { _ in
            let labels = app.exerciseRows.allElementsBoundByIndex.map(\.label)
            XCTAssertEqual(labels, [
                "Barbell bench press, 3 sets of 5 reps, 45 pounds",
                "Band pull-apart, 3 sets of 15 reps",
                "Band pull-apart, 3 sets of 15 reps",
                "Balance board hold, 3 sets of 30 seconds",
                "Barbell back squat, 3 sets of 5 reps, 45 pounds",
                "Biceps curl, 3 sets of 12 reps, 15 pounds per side",
                "Balance board hold, 3 sets of 30 seconds",
                "Barbell back squat, 3 sets of 5 reps, 45 pounds",
                "Push-up, 3 sets of 10 reps",
            ])
        }
        XCTContext.runActivity(named: "A tap on the small title scrolls back to the top") { _ in
            // The ninth row pushed Add exercise below Start, and the add scrolled to it.
            app.scrollToTop(titled: "Arm and back day")
            let smallTitle = app.navigationBars.firstMatch.buttons["Arm and back day"]
            XCTAssertTrue(smallTitle.disappears(), "The small title stayed with the title in view")
        }
    }

    /// Start rides above the keyboard while the title is edited, rather than staying behind it.
    /// A long press on the title shows the edit menu, and a long name shortened goes back to one
    /// line.
    @MainActor
    func startClearsKeyboard(in app: XCUIApplication, keyboard: XCUIElement) throws {
        let title = app.routineTitle
        let start = app.buttons["Start"]
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
        title.typeText("\n")
        XCTAssertTrue(keyboard.disappears(), "Return did not end the edit")
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
}

/// A built-in exercise as the picker labels it, the search that finds it when it is not in the
/// picker's first screenful, and its id for seeding.
struct BuiltInRow {
    let label: String
    let query: String?
    let id: String
}

@MainActor
extension XCUIApplication {
    /// The rows `testRenameAtDefaultSize` ends with and `RowDragUITests` seeds, in order. Nine
    /// run past one screen.
    static let nineExercises: [BuiltInRow] = [
        BuiltInRow(
            label: "Barbell bench press, Barbell, bench",
            query: nil,
            id: "barbell-bench-press",
        ),
        BuiltInRow(label: "Band pull-apart, Band", query: nil, id: "band-pull-apart"),
        BuiltInRow(label: "Band pull-apart, Band", query: nil, id: "band-pull-apart"),
        BuiltInRow(
            label: "Balance board hold, Balance board",
            query: nil,
            id: "balance-board-hold",
        ),
        BuiltInRow(label: "Barbell back squat, Barbell", query: nil, id: "barbell-back-squat"),
        BuiltInRow(label: "Biceps curl, Dumbbells", query: "biceps", id: "biceps-curl"),
        BuiltInRow(label: "Push-up", query: "push-up", id: "push-up"),
        BuiltInRow(
            label: "Balance board hold, Balance board",
            query: nil,
            id: "balance-board-hold",
        ),
        BuiltInRow(label: "Barbell back squat, Barbell", query: nil, id: "barbell-back-squat"),
    ]

    /// The rows `testRenameAtDefaultSize` seeds, and the one it then adds through search: the
    /// nine, with Push-up moved to the end.
    static var renameRows: (seeded: [BuiltInRow], added: BuiltInRow) {
        var rows = nineExercises
        let added = rows.remove(at: 6)
        return (rows, added)
    }

    /// Launches into a routine named `name` holding `nineExercises`, seeded, for the checks
    /// that only need the rows. Adding them is `testRenameAtDefaultSize`'s.
    func launchSeedingNineExercises(named name: String) {
        let title = launchSeeding(Self.nineExercises.map(\.id), named: name)
        XCTAssertEqual(title.value(becoming: name), name)
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
