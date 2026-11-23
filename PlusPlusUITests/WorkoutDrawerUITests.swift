import XCTest

/// The ++ drawer and the Workouts screen over saved workouts: the drawer's mark, a row's
/// Customize…, a built-in's hold menu in Add exercise, and the drill-in from the Workouts screen
/// and its filters.
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
            // An open workout is one of the Workouts, so their row is marked.
            XCTAssertTrue(app.buttons["Workouts"].isSelected, "Workouts is unmarked on a workout")
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
            // One +, floating at the bottom, none left in the bar.
            let new = app.buttons.matching(NSPredicate(format: "label == 'New workout'"))
            XCTAssertEqual(new.count, 1, "Workouts shows other than one New workout")
            XCTAssertGreaterThan(new.firstMatch.frame.midY, app.frame.midY, "The + isn't low")
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
            app.listedWorkout(named: "Chest").tap()
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
            app.listedWorkout(named: "Chest").tap()
            XCTAssertEqual(title.value(becoming: "Chest"), "Chest", "The row pushed no workout")
            typeName("Chest day", over: "Chest", in: app)
            app.tapBack()
            XCTAssertTrue(title.disappears(), "The chevron did not pop")
            let renamed = ["Chest day", "Back"]
            XCTAssertEqual(reading(app.workoutRowLabels, becoming: renamed, within: 2), renamed)
            attach(named: "chevron-renamed")
        }
        workoutsFilter(in: app)
    }

    /// The filters' wire, on "Chest day" (a barbell and a bench) and "Back" (a pull-up bar):
    /// a sheet of chips over the list narrows it behind the sheet, Also needs' + adds its piece
    /// to the filter, the Length sheet's wheel reaches the list, and Clear brings every workout
    /// back. Which workouts pass is `WorkoutFilterTests`'; the sheets over this screen's scroll
    /// view, the picker's wheel in one, and a button in the list writing the filter are the
    /// running app's.
    @MainActor
    private func workoutsFilter(in app: XCUIApplication) {
        let all = ["Chest day", "Back"]
        let clear = app.buttons["Clear filters"]
        let done = app.buttons["Done"]
        XCTContext.runActivity(named: "Muscle narrows Workouts, and Clear brings them back") { _ in
            let muscle = app.buttons["Muscle"]
            XCTAssertTrue(app.buttons["Equipment"].exists && app.buttons["Length"].exists)
            muscle.tap()
            let chest = app.scrollViews.buttons["Chest"]
            XCTAssertTrue(chest.appears(), "Muscle opened no sheet of chips")
            chest.tap()
            done.tap()
            XCTAssertTrue(chest.disappears(), "Done left the chips up")
            XCTAssertEqual(
                reading(app.workoutRowLabels, becoming: ["Chest day"], within: 2),
                ["Chest day"],
            )
            XCTAssertEqual(muscle.value as? String, "Chest")
            clear.tap()
            XCTAssertTrue(clear.disappears(), "Clear left a filter on")
            XCTAssertEqual(reading(app.workoutRowLabels, becoming: all, within: 2), all)
        }
        XCTContext.runActivity(named: "Also needs' + adds its piece to Equipment") { _ in
            app.buttons["Equipment"].tap()
            let barbell = app.scrollViews.buttons["Barbell"]
            XCTAssertTrue(barbell.appears(), "Equipment opened no sheet of chips")
            barbell.tap()
            done.tap()
            XCTAssertTrue(barbell.disappears(), "Done left the chips up")
            // Chest day, a bench short, is listed only under Also needs.
            let addBench = app.buttons["Add bench to Equipment"]
            XCTAssertTrue(addBench.appears(), "Chest day isn't listed as short a bench")
            addBench.tap()
            XCTAssertEqual(
                app.buttons["Equipment"].value(becoming: "Barbell, Bench"),
                "Barbell, Bench",
            )
            XCTAssertTrue(addBench.disappears(), "Also needs stayed once Bench was added")
            // Matches list first, over any heading.
            XCTAssertEqual(
                app.workoutRowLabels.first,
                "Chest day",
                "+ Bench didn't match Chest day",
            )
            clear.tap()
            XCTAssertTrue(clear.disappears(), "Clear left a filter on")
        }
        XCTContext.runActivity(named: "Length's wheel reaches the list") { _ in
            let length = app.buttons["Length"]
            length.tap()
            let upTo20 = app.buttons["20 minutes or less"]
            XCTAssertTrue(upTo20.appears(), "Length opened no presets")
            upTo20.tap()
            XCTAssertEqual(length.value(becoming: "20 minutes or less"), "20 minutes or less")
            // Past the right wheel's 20, the left carries it along: no workout is 25 minutes.
            app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "25 minutes")
            XCTAssertEqual(length.value(becoming: "25 minutes"), "25 minutes")
            done.tap()
            XCTAssertTrue(upTo20.disappears(), "Done left the Length sheet up")
            XCTAssertEqual(app.workoutRowLabels, [], "A 25 minute filter kept a workout")
            clear.tap()
            XCTAssertEqual(reading(app.workoutRowLabels, becoming: all, within: 2), all)
        }
        logTurnsFiltersOff(in: app, showing: all)
    }

    /// A filter on over Workouts is off after a visit to Log through the drawer, and every
    /// workout is listed again: the filter is the Workouts screen's own, gone with the screen,
    /// which only the running app shows.
    @MainActor
    private func logTurnsFiltersOff(in app: XCUIApplication, showing all: [String]) {
        XCTContext.runActivity(named: "A visit to Log turns Workouts' filters off") { _ in
            let clear = app.buttons["Clear filters"]
            app.buttons["Muscle"].tap()
            let chest = app.scrollViews.buttons["Chest"]
            XCTAssertTrue(chest.appears(), "Muscle opened no sheet of chips")
            chest.tap()
            app.buttons["Done"].tap()
            XCTAssertTrue(chest.disappears(), "Done left the chips up")
            XCTAssertTrue(clear.exists, "Chest turned no filter on")
            app.openDrawer(andTap: "Log")
            XCTAssertEqual(reading(app.workoutRowLabels, becoming: [], within: 2), [])
            app.openDrawer(andTap: "Workouts")
            XCTAssertEqual(reading(app.workoutRowLabels, becoming: all, within: 2), all)
            XCTAssertFalse(clear.exists, "A filter is on after a visit to Log")
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
