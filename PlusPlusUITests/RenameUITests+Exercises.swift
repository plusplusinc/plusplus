import XCTest

/// Adding exercises, within `testRenameAtDefaultSize`, so it shares its launch. Deleting is
/// `RowDragUITests`'.
@MainActor
extension RenameUITests {
    /// The picker opens fast and without the keyboard, and a pick adds a row, Start rising with
    /// the + above it. The rest of the rows are
    /// seeded at the test's launch, in a routine the drawer then opens, and one more is added
    /// through the picker's search onto them. Search's list and empty state are left to use, and
    /// the add's scroll to the list's end is `TitleWrappingUITests`' at AX5. Where the + sits, to
    /// the point, is `PrimaryKeyBarTests`'.
    func addExercises(in app: XCUIApplication, keyboard: XCUIElement) {
        let search = app.searchFields.firstMatch
        let start = app.buttons["Start"]
        let plus = app.buttons["Add exercise"]
        // At rest, before the picker covers it.
        let low = plus.frame
        openPickerFromEmptySpace(in: app, keyboard: keyboard)
        let (seeded, added) = XCUIApplication.renameRows
        XCTContext
            .runActivity(named: "Start appears with the first exercise, the + above it") { _ in
                app.pickerRows[seeded[0].label].tap()
                XCTAssertTrue(search.disappears(), "The add left the picker open")
                XCTAssertEqual(app.exerciseCount(becoming: 1), 1, "The pick added no row")
                // What Start does is `WorkoutUITests`'.
                XCTAssertTrue(start.appears())
                XCTAssertTrue(
                    app.noExercises.disappears(),
                    "No exercises stayed with an exercise in",
                )
                XCTAssertTrue(start.settles() && plus.settles(), "Start or the + kept moving")
                XCTAssertGreaterThan(low.maxY, start.frame.minY, "The + sat no lower with no Start")
                XCTAssertLessThanOrEqual(
                    plus.frame.maxY,
                    start.frame.minY,
                    "The + is not above Start",
                )
            }
        XCTContext.runActivity(named: "An add through search lands after seeded rows") { _ in
            app.openDrawer(andTap: Self.seededName)
            XCTAssertEqual(app.routineTitle.value(becoming: Self.seededName), Self.seededName)
            XCTAssertEqual(app.exerciseCount(becoming: seeded.count), seeded.count)
            app.addExercise(added.label, searching: added.query)
            attach(named: "nine-exercises")
        }
        XCTContext.runActivity(named: "Rows read as name and plan") { _ in
            let labels = app.exerciseRowLabels
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
            // The ninth row went in under the +, and the add scrolled to the list's end.
            app.scrollToTop(titled: Self.seededName)
            let smallTitle = app.navigationBars.firstMatch.buttons[Self.seededName]
            XCTAssertTrue(smallTitle.disappears(), "The small title stayed with the title in view")
        }
    }

    /// On an empty routine, a tap in the empty space opens the picker, unless all it did was end
    /// the title's edit: through the tap gesture and the touch-down that ends the edit, which
    /// only the running app arbitrates.
    private func openPickerFromEmptySpace(in app: XCUIApplication, keyboard: XCUIElement) {
        let search = app.searchFields.firstMatch
        // The line takes no touches, so a tap on it lands on the screen's empty space.
        let emptySpace = app.noExercises.center
        XCTContext.runActivity(named: "A tap that ends the title's edit opens no picker") { _ in
            XCTAssertTrue(app.noExercises.exists, "An empty routine shows no No exercises")
            app.routineTitle.tap()
            XCTAssertTrue(keyboard.appears(), "A tap on the title did not start an edit")
            emptySpace.tap()
            XCTAssertTrue(keyboard.disappears(), "The tap on empty space did not end the edit")
            // The keyboard's element goes before a sheet the tap opened would be in the tree.
            XCTAssertFalse(
                search.appears(within: 1),
                "The tap that ended the edit opened the picker",
            )
        }
        XCTContext.runActivity(named: "A tap in an empty routine's space opens the picker") { _ in
            XCTAssertFalse(app.buttons["Start"].exists, "Start shows with no exercises")
            emptySpace.tap()
            XCTAssertTrue(search.appears(within: 1), "The tap on empty space opened no picker")
            XCTAssertFalse(keyboard.exists, "Search took focus when the picker opened")
            XCTAssertEqual(app.pickerRows.firstMatch.label, "Backward arm circles")
        }
    }

    /// Start rides above the keyboard while the title is edited, rather than staying behind it.
    /// A long press on the title shows the edit menu, and a long name shortened goes back to one
    /// line.
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
        title.typeText("\n")
        XCTAssertTrue(keyboard.disappears(), "Return did not end the edit")
        // The keyboard's element goes before the keyboard has finished going down. Pressed
        // 0.1 s after Return, in a full parallel run, the long press once showed no edit menu,
        // so it waits for the edit's end to finish: Start back where it rests.
        XCTAssertEqual(
            reading(start.frame, becoming: atRest, within: 2),
            atRest,
            "Start did not go back down with the keyboard",
        )
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
