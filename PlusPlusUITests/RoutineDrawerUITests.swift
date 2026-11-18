import XCTest

/// The ++ drawer, the Routines screen over saved routines, and Exercises: the drawer's two places
/// and its mark, the drill-in from the Routines screen, and Exercises' search covering ++. Which
/// routines come first is `RoutineStoreRecencyTests`'. Names come from the muscle groups
/// (`-fallbackNames`). A name typed on a pushed routine and left with no Return shows in the list
/// once popped, which only the session's save puts there; that a save reaches the store is
/// `RoutineSessionTests`', and that one survives a quit `RoutineAutosaveUITests`'.
///
/// `nonisolated` because XCTestCase's initializers are; the test drives the UI on the main actor.
final nonisolated class RoutineDrawerUITests: XCTestCase {
    /// On a saved routine opened with exercises in, a tap in the empty space below the last row
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

    /// From one saved routine, the drawer's places, a second routine made and both opened from
    /// the Routines screen, and Exercises.
    @MainActor
    func testDrawerSwitchesRoutines() {
        let app = XCUIApplication()
        // Seeded, since the add is `RoutineAutosaveUITests`'.
        let title = app.launchSeeding(["barbell-bench-press"], arguments: ["-fallbackNames", "YES"])
        openPickerFromBelowRows(in: app)
        XCTContext.runActivity(named: "The drawer offers Routines and Exercises") { _ in
            XCTAssertEqual(title.value(becoming: "Chest"), "Chest")
            XCTAssertTrue(app.buttons["Add exercise"].exists)
            openDrawer(in: app)
            XCTAssertTrue(app.buttons["Start"].disappears(), "VoiceOver reaches Start behind it")
            XCTAssertTrue(
                app.buttons["Add exercise"].disappears(),
                "VoiceOver reaches Add exercise behind it",
            )
            // A routine showing is neither place.
            XCTAssertFalse(app.buttons["Routines"].isSelected, "Routines is marked on a routine")
            XCTAssertFalse(app.buttons["Exercises"].isSelected, "Exercises is marked on a routine")
            attach(named: "drawer-routine")
            app.drawerTitle.tap()
            XCTAssertTrue(app.drawerTitle.disappears(), "Tapping the title left the drawer open")
            XCTAssertEqual(title.value as? String, "Chest")
        }
        routinesScreenDrillsIn(in: app, title: title)
        exercisesSearchCoversMenu(in: app)
        exercisesCustomizesAndDeletes(in: app)
    }

    /// The Routines screen lists every routine, latest first; a row or + pushes a routine with a
    /// back chevron in place of ++, which the chevron or an edge swipe pops; the chevron keeps a
    /// name still being typed. Each key reaches the routine as typed, whichever way the screen
    /// goes, so the chevron, which ends no edit, shows it for the edge swipe too.
    @MainActor
    private func routinesScreenDrillsIn(in app: XCUIApplication, title: XCUIElement) {
        XCTContext.runActivity(named: "Routines lists every routine, and + pushes a new one") { _ in
            app.openDrawer(andTap: "Routines")
            XCTAssertEqual(reading(app.routineRowLabels, becoming: ["Chest"], within: 2), ["Chest"])
            openDrawer(in: app)
            XCTAssertTrue(app.buttons["Routines"].isSelected, "Routines isn't marked")
            XCTAssertFalse(app.buttons["Exercises"].isSelected)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            XCTAssertTrue(app.drawerTitle.disappears(), "A tap on the sliver left it open")
            app.buttons["New routine"].tap()
            XCTAssertEqual(title.value(becoming: "New routine"), "New routine")
            app.tapBack()
            XCTAssertTrue(title.disappears(), "The chevron did not pop")
            XCTAssertEqual(app.routineRowLabels, ["Chest"], "The untouched new one was listed")
            app.buttons["New routine"].tap()
            XCTAssertEqual(title.value(becoming: "New routine"), "New routine")
            app.addExercise("Pull-up, Pull-up bar", searching: "pullup")
            XCTAssertEqual(title.value(becoming: "Back"), "Back")
            XCTAssertFalse(app.buttons["Menu"].exists, "++ shows on a pushed routine")
            attach(named: "pushed-routine")
            app.edgeSwipe()
            XCTAssertTrue(title.disappears(), "The edge swipe did not pop")
            XCTAssertFalse(app.drawerTitle.exists, "The edge swipe opened the drawer")
            XCTAssertTrue(app.buttons["Menu"].appears(), "No ++ back on the Routines screen")
            let listed = ["Back", "Chest"]
            XCTAssertEqual(reading(app.routineRowLabels, becoming: listed, within: 2), listed)
            attach(named: "routines-screen")
        }
        XCTContext.runActivity(named: "A row pushes its routine, and an edit moves it up") { _ in
            app.routineRow(named: "Chest").tap()
            XCTAssertEqual(title.value(becoming: "Chest"), "Chest", "The row pushed no routine")
            XCTAssertEqual(app.exerciseNames, ["Barbell bench press"])
            editTheFirstRow(in: app)
            app.tapBack()
            XCTAssertTrue(title.disappears(), "The chevron did not pop")
            let listed = ["Chest", "Back"]
            XCTAssertEqual(
                reading(app.routineRowLabels, becoming: listed, within: 2),
                listed,
                "The edited one isn't first",
            )
        }
        XCTContext.runActivity(named: "The chevron keeps a name still being typed") { _ in
            app.routineRow(named: "Chest").tap()
            XCTAssertEqual(title.value(becoming: "Chest"), "Chest", "The row pushed no routine")
            typeName("Chest day", over: "Chest", in: app)
            app.tapBack()
            XCTAssertTrue(title.disappears(), "The chevron did not pop")
            let renamed = ["Chest day", "Back"]
            XCTAssertEqual(reading(app.routineRowLabels, becoming: renamed, within: 2), renamed)
            attach(named: "chevron-renamed")
        }
    }

    /// On the routine showing, opens its first row's sheet, adds a set, drags the weight ruler,
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

    /// Types `name` over the pushed routine's `old` one, with no Return, so it is still being
    /// edited.
    @MainActor
    private func typeName(_ name: String, over old: String, in app: XCUIApplication) {
        let keyboard = app.keyboards.element
        XCTAssertNoThrow(try app.routineTitle.typeOver(old, with: name, keyboard: keyboard))
        XCTAssertEqual(app.routineTitle.value(becoming: name), name)
    }

    /// From the Routines screen, the drawer's Exercises shows the exercise list, marked in the
    /// drawer. Its open search's field covers ++, which then takes no tap and is out of
    /// VoiceOver's reach, and the search's X uncovers it; the edge swipe opens the drawer with
    /// the search open. The cover's motion is checked on frames; the bar's item and its
    /// accessibility only the running app composes.
    @MainActor
    private func exercisesSearchCoversMenu(in app: XCUIApplication) {
        XCTContext.runActivity(named: "Exercises' search covers ++ while it is open") { _ in
            app.openDrawer(andTap: "Exercises")
            let menu = app.buttons["Menu"]
            XCTAssertTrue(app.searchButton.appears(), "Exercises showed no search")
            XCTAssertTrue(menu.exists, "Exercises showed no ++")
            XCTAssertEqual(app.barElements, ["button Menu", "button Search"])
            let circle = app.searchButton.frame
            XCTAssertEqual(circle.width, circle.height, accuracy: 1, "Search isn't its circle")
            XCTAssertLessThanOrEqual(circle.maxX, app.frame.maxX, "Search runs off the screen")
            // From its frame now: a coordinate on the element resolves it when tapped.
            let menuPoint = app.point(x: menu.frame.midX, y: menu.frame.midY)
            app.searchButton.tap()
            XCTAssertTrue(menu.disappears(), "VoiceOver reaches ++ under the open search")
            XCTAssertTrue(app.keyboards.element.appears(), "The open search took no focus")
            XCTAssertEqual(app.barElements, ["field Search", "button Close search"])
            XCTAssertEqual(app.searchButton.frame, circle, "Close search isn't the circle")
            XCTAssertLessThanOrEqual(
                app.searchField.frame.maxX,
                circle.minX,
                "The field runs under Close search",
            )
            attach(named: "exercises-searching")
            menuPoint.tap()
            XCTAssertFalse(app.drawerTitle.appears(within: 1), "A tap on the covered ++ landed")
            app.edgeSwipe()
            XCTAssertTrue(app.drawerTitle.appears(), "The edge swipe did not open the drawer")
            XCTAssertTrue(app.buttons["Exercises"].isSelected, "Exercises isn't marked")
            app.drawerTitle.tap()
            XCTAssertTrue(app.drawerTitle.disappears(), "Tapping the title left the drawer open")
            app.searchButton.tap()
            XCTAssertTrue(menu.appears(), "The search's X did not uncover ++")
            XCTAssertEqual(app.barElements, ["button Menu", "button Search"])
        }
    }

    /// In Exercises, a built-in's row opens nothing; Create in the search stores the exercise
    /// and pushes its Customize form, with no Save or Cancel, and back comes to the list, where
    /// it shows; a tap on it pushes the form again; and Delete asks before it deletes, then comes
    /// back to a list without it. What a customize or delete does to the routines, and the count
    /// the question gives, are the package's (`RoutineStoreCustomizeTests`,
    /// `RoutineSessionExerciseTests`); this holds the wire through the screen's pushes and the
    /// question, which only the running app composes.
    @MainActor
    private func exercisesCustomizesAndDeletes(in app: XCUIApplication) {
        XCTContext.runActivity(named: "Exercises creates, customizes, and deletes") { _ in
            let name = app.textFields["customize.name"]
            let builtIn = app.descendants(matching: .any)
                .matching(identifier: "exercises.row").firstMatch
            XCTAssertTrue(builtIn.appears(), "Exercises listed nothing")
            XCTAssertFalse(builtIn.elementType == .button, "A built-in's row takes a tap")
            builtIn.tap()
            XCTAssertFalse(name.appears(within: 1), "A built-in's row opened a form")

            app.search(for: "zq")
            XCTAssertEqual(app.searchField.value as? String, "zq", "The search capitalized")
            let create = app.buttons["picker.create"]
            XCTAssertTrue(create.appears(), "Exercises' search offered no Create")
            XCTAssertEqual(
                create.label,
                "Create \u{201C}Zq\u{201D}",
                "Create's row doesn't show the name it creates",
            )
            create.tap()
            XCTAssertTrue(name.appears(), "Create pushed no Customize form")
            XCTAssertEqual(name.value as? String, "Zq", "Create's name isn't capitalized")
            XCTAssertFalse(app.buttons["Save"].exists, "Customize has a Save")
            XCTAssertFalse(app.buttons["Cancel"].exists, "Customize has a Cancel")
            app.tapBack()
            let row = app.pickerRows["Zq"]
            XCTAssertTrue(row.appears(), "The created exercise isn't in the list")
            XCTAssertTrue(row.settles(), "The created exercise's row kept moving")
            row.tap()
            XCTAssertTrue(name.appears(), "A created exercise's row opened no Customize form")

            app.buttons["Delete exercise"].tap()
            let question = app.staticTexts["Delete Zq?"]
            XCTAssertTrue(question.appears(), "Delete didn't ask first")
            XCTAssertTrue(name.exists, "Delete left the form before an answer")
            let confirm = app.buttons.matching(identifier: "Delete exercise")
            XCTAssertEqual(confirm.count, 2, "The question offers no Delete exercise")
            let answer = confirm.element(boundBy: 1)
            XCTAssertTrue(answer.settles(), "The question's Delete exercise kept moving")
            answer.tap()
            XCTAssertTrue(name.disappears(), "Delete didn't come back to the list")
            XCTAssertTrue(row.disappears(), "The deleted exercise is still listed")
            XCTAssertTrue(create.appears(), "Its name isn't free to create again")
        }
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
