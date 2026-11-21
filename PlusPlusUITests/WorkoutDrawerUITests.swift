import XCTest

/// The ++ drawer and the Workouts screen over saved workouts: the drawer's mark, a row's
/// Customize…, a built-in's hold menu in Add exercise, and the drill-in from the Workouts screen.
/// Which workouts come first is `StoreRecencyTests`'. Names come from the muscle groups
/// (`-fallbackNames`). A name typed on a pushed workout and left with no Return shows in the list
/// once popped, which only the session's save puts there; that a save reaches the store is
/// `AppSessionTests`', and that one survives a quit `WorkoutAutosaveUITests`'.
///
/// `nonisolated` because XCTestCase's initializers are; the test drives the UI on the main actor.
final nonisolated class WorkoutDrawerUITests: XCTestCase {
    /// On a saved workout opened with exercises in, a tap in the empty space below the last row
    /// opens the picker at half height, as the first sheet the screen opens. Here, not after a
    /// pick, because the first opening is where a height set from the last one showed full. The
    /// picker's search is a bar button until tapped, so its Close, in the same bar, marks the
    /// sheet's top.
    @MainActor
    private func openPickerFromBelowRows(in app: XCUIApplication) {
        let close = app.buttons["Close"]
        XCTContext.runActivity(named: "A tap below the last row opens the picker half up") { _ in
            app.exerciseRows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1))
                .withOffset(CGVector(dx: 0, dy: 120)).tap()
            XCTAssertTrue(close.appears(within: 2), "The tap below the last row opened no picker")
            XCTAssertGreaterThan(
                close.frame.minY,
                app.frame.height / 3,
                "The picker opened full height from a tap below the rows",
            )
            close.tap()
            XCTAssertTrue(close.disappears(), "Close left the picker up")
        }
    }

    /// From one saved workout, the drawer, a row's Customize…, a second workout made and both
    /// opened from the Workouts screen, and both deleted.
    @MainActor
    func testDrawerSwitchesWorkouts() {
        let app = XCUIApplication()
        // Seeded, since the add is `WorkoutAutosaveUITests`'.
        let title = app.launchSeeding(["barbell-bench-press"], arguments: ["-fallbackNames", "YES"])
        openPickerFromBelowRows(in: app)
        XCTContext.runActivity(named: "The drawer offers Workouts") { _ in
            XCTAssertEqual(title.value(becoming: "Chest"), "Chest")
            XCTAssertTrue(app.buttons["Add exercise"].exists)
            openDrawer(in: app)
            XCTAssertTrue(app.buttons["Start"].disappears(), "VoiceOver reaches Start behind it")
            XCTAssertTrue(
                app.buttons["Add exercise"].disappears(),
                "VoiceOver reaches Add exercise behind it",
            )
            // A workout showing isn't Workouts.
            XCTAssertFalse(app.buttons["Workouts"].isSelected, "Workouts is marked on a workout")
            attach(named: "drawer-workout")
            app.drawerTitle.tap()
            XCTAssertTrue(app.drawerTitle.disappears(), "Tapping the title left the drawer open")
            XCTAssertEqual(title.value as? String, "Chest")
        }
        rowCustomizes(in: app)
        builtInHoldMenuCustomizes(in: app)
        customizeInPickerDeletes(in: app)
        workoutsScreenDrillsIn(in: app, title: title)
        workoutsDeleteWorkouts(in: app, title: title)
    }

    /// The Workouts screen lists every workout, latest first; a row or + pushes a workout with a
    /// back chevron in place of ++, which the chevron or an edge swipe pops; the chevron keeps a
    /// name still being typed. Each key reaches the workout as typed, whichever way the screen
    /// goes, so the chevron, which ends no edit, shows it for the edge swipe too.
    @MainActor
    private func workoutsScreenDrillsIn(in app: XCUIApplication, title: XCUIElement) {
        XCTContext.runActivity(named: "Workouts lists every workout, and + pushes a new one") { _ in
            app.openDrawer(andTap: "Workouts")
            XCTAssertEqual(reading(app.workoutRowLabels, becoming: ["Chest"], within: 2), ["Chest"])
            openDrawer(in: app)
            XCTAssertTrue(app.buttons["Workouts"].isSelected, "Workouts isn't marked")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            XCTAssertTrue(app.drawerTitle.disappears(), "A tap on the sliver left it open")
            app.buttons["New workout"].tap()
            XCTAssertEqual(title.value(becoming: "New workout"), "New workout")
            newWorkoutDimsDelete(in: app)
            app.tapBack()
            XCTAssertTrue(title.disappears(), "The chevron did not pop")
            XCTAssertEqual(app.workoutRowLabels, ["Chest"], "The untouched new one was listed")
            app.buttons["New workout"].tap()
            XCTAssertEqual(title.value(becoming: "New workout"), "New workout")
            app.addExercise("Pull-up, Pull-up bar", searching: "pullup")
            XCTAssertEqual(title.value(becoming: "Back"), "Back")
            XCTAssertFalse(app.buttons["Menu"].exists, "++ shows on a pushed workout")
            attach(named: "pushed-workout")
            app.edgeSwipe()
            XCTAssertTrue(title.disappears(), "The edge swipe did not pop")
            XCTAssertFalse(app.drawerTitle.exists, "The edge swipe opened the drawer")
            XCTAssertTrue(app.buttons["Menu"].appears(), "No ++ back on the Workouts screen")
            let listed = ["Back", "Chest"]
            XCTAssertEqual(reading(app.workoutRowLabels, becoming: listed, within: 2), listed)
            attach(named: "workouts-screen")
        }
        XCTContext.runActivity(named: "A row pushes its workout, and an edit moves it up") { _ in
            app.workoutRow(named: "Chest").tap()
            XCTAssertEqual(title.value(becoming: "Chest"), "Chest", "The row pushed no workout")
            XCTAssertEqual(app.exerciseNames, ["Barbell bench press"])
            editTheFirstRow(in: app)
            app.tapBack()
            XCTAssertTrue(title.disappears(), "The chevron did not pop")
            let listed = ["Chest", "Back"]
            XCTAssertEqual(
                reading(app.workoutRowLabels, becoming: listed, within: 2),
                listed,
                "The edited one isn't first",
            )
        }
        XCTContext.runActivity(named: "The chevron keeps a name still being typed") { _ in
            app.workoutRow(named: "Chest").tap()
            XCTAssertEqual(title.value(becoming: "Chest"), "Chest", "The row pushed no workout")
            typeName("Chest day", over: "Chest", in: app)
            app.tapBack()
            XCTAssertTrue(title.disappears(), "The chevron did not pop")
            let renamed = ["Chest day", "Back"]
            XCTAssertEqual(reading(app.workoutRowLabels, becoming: renamed, within: 2), renamed)
            attach(named: "chevron-renamed")
        }
    }

    /// On the workout showing, opens its first row's sheet, adds a set, drags the weight ruler,
    /// and closes the sheet.
    @MainActor
    private func editTheFirstRow(in app: XCUIApplication) {
        app.exerciseRows.element(boundBy: 0).tap()
        let sets = app.buttons["Sets"]
        XCTAssertTrue(sets.appears(), "Tapping a row opened no sheet")
        sets.tap()
        app.buttons["Increase"].tapAtCenter()
        XCTAssertEqual(sets.value(becoming: "4 sets"), "4 sets")
        dragTheWeightRuler(in: app)
        app.buttons["Close"].tap()
        XCTAssertTrue(sets.disappears(), "Close left the sheet up")
    }

    /// In the open sheet, at half height, Weight opening grows the sheet to fit it, and a drag
    /// at a hand's speed on the ruler under its keys raises the weight. The sheet's heights are
    /// the system's, and the ruler is a scroll view: whether its drag wins over the sheet's and
    /// over the ruler's own hold on its value shows only in the running app, as does whether its
    /// labels reach the accessibility tree. Where a drag lands is `RulerScaleTests`'. The sheet is
    /// one this test already has open, so the check costs a
    /// tap and a drag.
    @MainActor
    private func dragTheWeightRuler(in app: XCUIApplication) {
        let weight = app.buttons["Weight"]
        XCTAssertEqual(weight.value as? String, "45 pounds")
        weight.tap()
        let increase = app.buttons["Increase"]
        // Weight's keys take the place of Sets' as one row shuts and the next opens.
        XCTAssertTrue(increase.settles(), "The stepper kept moving after Weight opened")
        // The half-height sheet grows to hold the open row, so the row after it stays whole.
        let rest = app.buttons["Rest, After each set"]
        XCTAssertTrue(rest.settles(), "The sheet kept moving after Weight opened")
        XCTAssertLessThanOrEqual(
            rest.frame.maxY,
            app.frame.maxY,
            "The sheet did not grow to fit the open Weight row",
        )
        let ruler = app.point(x: increase.frame.minX, y: increase.frame.maxY + 30)
        ruler.press(
            forDuration: 0.05,
            thenDragTo: ruler.withOffset(CGVector(dx: -80, dy: 0)),
            withVelocity: XCUIGestureVelocity(300),
            thenHoldForDuration: 0.2,
        )
        let pounds = reading(Self.pounds(weight), until: { $0 > 45 }, within: 2)
        XCTAssertGreaterThan(pounds, 45, "A drag on the ruler toward heavier left the weight")
        attach(named: "ruler-dragged")
        // The row steps the value for VoiceOver; the ruler's labels, between its keys and the
        // next row, are decoration. Hosted, they never reached the tree, so only the running app
        // shows this.
        let below = increase.frame.maxY
        let band = below ... max(below, rest.frame.minY)
        let labels = app.snapshots { $0.elementType == .staticText && band.contains($0.frame.midY) }
        XCTAssertEqual(
            labels.map(\.label),
            [],
            "The ruler's labels are in the accessibility tree",
        )
    }

    /// The number a Weight row's value starts with, "49.5 pounds", or 0 with none.
    @MainActor
    private static func pounds(_ weight: XCUIElement) -> Double {
        let value = weight.value as? String ?? ""
        return Double(value.prefix { $0.isNumber || $0 == "." }) ?? 0
    }

    /// Types `name` over the pushed workout's `old` one, with no Return, so it is still being
    /// edited.
    @MainActor
    private func typeName(_ name: String, over old: String, in app: XCUIApplication) {
        let keyboard = app.keyboards.element
        XCTAssertNoThrow(try app.workoutTitle.typeOver(old, with: name, keyboard: keyboard))
        XCTAssertEqual(app.workoutTitle.value(becoming: name), name)
    }

    @MainActor
    private func openDrawer(in app: XCUIApplication) {
        app.buttons["Menu"].tap()
        XCTAssertTrue(app.drawerTitle.appears(), "++ did not open the drawer")
        // The bars are hosted apart from the screen, and their controls leave the tree on their
        // own, so the drawer's buttons are read only once they have.
        XCTAssertTrue(app.buttons["Menu"].disappears(), "VoiceOver reaches ++ behind the drawer")
    }
}
