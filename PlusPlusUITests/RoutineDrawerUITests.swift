import XCTest

/// The ++ drawer and the Routines screen over saved routines: switching, a title opened and
/// left as it was saving nothing, and the drill-in from the Routines screen. Opening counting as
/// using is `RoutineStoreRecencyTests`', through the
/// `openRoutine` a switch already shows it called. Names come from the muscle groups
/// (`-fallbackNames`). A name typed on a pushed routine and left with no Return shows in the list
/// once popped, which only the session's save puts there; that a save reaches the store is
/// `RoutineSessionTests`', and that one survives a quit `RoutineAutosaveUITests`'.
///
/// `nonisolated` because XCTestCase's initializers are; the test drives the UI on the main actor.
final nonisolated class RoutineDrawerUITests: XCTestCase {
    /// From one saved routine, a second made, the two switched between, and both opened from
    /// the Routines screen.
    @MainActor
    func testDrawerSwitchesRoutines() {
        let app = XCUIApplication()
        // Seeded, since the add is `RoutineAutosaveUITests`'.
        let title = app.launchSeeding(["barbell-bench-press"], arguments: ["-fallbackNames", "YES"])
        XCTContext.runActivity(named: "The drawer marks the routine showing, or a new one") { _ in
            XCTAssertEqual(title.value(becoming: "Chest"), "Chest")
            XCTAssertTrue(app.buttons["Add exercise"].exists)
            openDrawer(in: app)
            XCTAssertEqual(drawerRoutines(in: app), ["Chest"])
            XCTAssertTrue(app.buttons["Start"].disappears(), "VoiceOver reaches Start behind it")
            XCTAssertTrue(
                app.buttons["Add exercise"].disappears(),
                "VoiceOver reaches Add exercise behind it",
            )
            XCTAssertTrue(app.buttons["Chest"].isSelected, "The routine showing isn't marked")
            XCTAssertFalse(app.buttons["Routines"].isSelected)
            attach(named: "drawer-routine")
            app.buttons["New"].tap()
            XCTAssertTrue(app.drawerTitle.disappears(), "New did not close the drawer")
            XCTAssertEqual(title.value(becoming: "New routine"), "New routine")
            XCTAssertEqual(app.exerciseRows.count, 0)
            openDrawer(in: app)
            XCTAssertEqual(drawerRoutines(in: app), ["New routine", "Chest"])
            XCTAssertTrue(app.buttons["New routine"].isSelected, "The new one isn't marked")
            XCTAssertFalse(app.buttons["New"].isSelected, "New, an action, is marked")
            XCTAssertFalse(app.buttons["Chest"].isSelected)
            // The untouched new routine's row only closes the drawer.
            app.buttons["New routine"].tap()
            XCTAssertTrue(app.drawerTitle.disappears(), "The new one's row left the drawer open")
            XCTAssertEqual(title.value as? String, "New routine")
        }
        XCTContext.runActivity(named: "Switching keeps both, and opening keeps the order") { _ in
            app.addExercise("Pull-up, Pull-up bar", searching: "pull-up")
            XCTAssertEqual(title.value(becoming: "Back"), "Back")
            openDrawer(in: app)
            XCTAssertEqual(drawerRoutines(in: app), ["Back", "Chest"])
            app.buttons["Chest"].tap()
            XCTAssertTrue(app.drawerTitle.disappears(), "Opening a routine left the drawer open")
            XCTAssertEqual(title.value(becoming: "Chest"), "Chest")
            XCTAssertEqual(app.exerciseNames, ["Barbell bench press"])
            openDrawer(in: app)
            // Opened from the drawer, it keeps its place there, and only the mark moves.
            XCTAssertEqual(drawerRoutines(in: app), ["Back", "Chest"], "Opening one moved it")
            XCTAssertTrue(app.buttons["Chest"].isSelected, "The routine opened isn't marked")
            XCTAssertFalse(app.buttons["Back"].isSelected)
        }
        untouchedEditKeepsThePlace(in: app, title: title)
        drawerEditMovesUp(in: app)
        routinesScreenDrillsIn(in: app, title: title)
    }

    /// With the drawer open on Back over Chest, Chest showing: Chest's title opened and left as it
    /// was with Return is no change, so nothing is saved and Chest keeps its place under Back.
    /// Leaves the drawer open.
    @MainActor
    private func untouchedEditKeepsThePlace(in app: XCUIApplication, title: XCUIElement) {
        XCTContext.runActivity(named: "A title opened and left as it was moves nothing") { _ in
            app.drawerTitle.tap()
            XCTAssertTrue(app.drawerTitle.disappears(), "Tapping the title left the drawer open")
            // The screen slides back from the drawer's side.
            XCTAssertTrue(title.settles(), "The title kept moving after the drawer shut")
            let keyboard = app.keyboards.element
            title.tap()
            XCTAssertTrue(keyboard.appears(), "Tapping the title opened no keyboard")
            title.typeText("\n")
            XCTAssertTrue(keyboard.disappears(), "Return should end editing")
            XCTAssertEqual(title.value(becoming: "Chest"), "Chest")
            openDrawer(in: app)
            XCTAssertEqual(drawerRoutines(in: app), ["Back", "Chest"], "No change moved it up")
        }
    }

    /// With the drawer open on Back over Chest, Chest showing: editing Chest puts it first in the
    /// drawer, without a relaunch. Leaves the drawer open.
    @MainActor
    private func drawerEditMovesUp(in app: XCUIApplication) {
        XCTContext.runActivity(named: "Editing a routine moves it to the top of the drawer") { _ in
            app.drawerTitle.tap()
            XCTAssertTrue(app.drawerTitle.disappears(), "Tapping the title left the drawer open")
            app.exerciseRows.element(boundBy: 0).tap()
            let sets = app.buttons["Sets"]
            XCTAssertTrue(sets.appears(), "Tapping a row opened no sheet")
            sets.tap()
            app.buttons["Increase"].tapAtCenter()
            XCTAssertEqual(sets.value(becoming: "4 sets"), "4 sets")
            dragTheWeightRuler(in: app)
            app.buttons["Close"].tap()
            XCTAssertTrue(sets.disappears(), "Close left the sheet up")
            openDrawer(in: app)
            XCTAssertEqual(drawerRoutines(in: app), ["Chest", "Back"], "The edited one isn't first")
        }
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

    /// The Routines screen lists every routine, latest first; a row or + pushes a routine with a
    /// back chevron in place of ++, which the chevron or an edge swipe pops; the chevron keeps a
    /// name still being typed. Each key reaches the routine as typed, whichever way the screen
    /// goes, so the chevron, which ends no edit, shows it for the edge swipe too.
    @MainActor
    private func routinesScreenDrillsIn(in app: XCUIApplication, title: XCUIElement) {
        XCTContext.runActivity(named: "Routines lists every routine, and a row drills in") { _ in
            app.buttons["Routines"].tap()
            XCTAssertTrue(app.drawerTitle.disappears(), "Routines did not close the drawer")
            let rows = app.buttons.matching(identifier: "routines.row")
            let listed = ["Chest", "Back"]
            XCTAssertEqual(reading(app.routineRowLabels, becoming: listed, within: 2), listed)
            attach(named: "routines-screen")
            openDrawer(in: app)
            XCTAssertTrue(app.buttons["Routines"].isSelected, "Routines isn't marked")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            XCTAssertTrue(app.drawerTitle.disappears(), "A tap on the sliver left it open")
            rows.element(boundBy: 1).tap()
            XCTAssertEqual(title.value(becoming: "Back"), "Back", "The row pushed no routine")
            XCTAssertFalse(app.buttons["Menu"].exists, "++ shows on a pushed routine")
            attach(named: "pushed-routine")
            app.edgeSwipe()
            XCTAssertTrue(title.disappears(), "The edge swipe did not pop")
            XCTAssertFalse(app.drawerTitle.exists, "The edge swipe opened the drawer")
            XCTAssertTrue(app.buttons["Menu"].appears(), "No ++ back on the Routines screen")
        }
        XCTContext.runActivity(named: "+ pushes a new routine, and the chevron pops it") { _ in
            app.buttons["New routine"].tap()
            XCTAssertEqual(title.value(becoming: "New routine"), "New routine")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(title.disappears(), "The chevron did not pop")
            app.edgeSwipe()
            XCTAssertTrue(app.drawerTitle.appears(), "The edge swipe on Routines did not open it")
            app.drawerTitle.tap()
            XCTAssertTrue(app.drawerTitle.disappears(), "Tapping the title left the drawer open")
        }
        XCTContext.runActivity(named: "The chevron keeps a name still being typed") { _ in
            // By name: opening Back may have moved it up the list.
            app.buttons.matching(identifier: "routines.row")
                .matching(NSPredicate(format: "label == %@", "Chest")).firstMatch.tap()
            XCTAssertEqual(title.value(becoming: "Chest"), "Chest", "The row pushed no routine")
            typeName("Chest day", over: "Chest", in: app)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(title.disappears(), "The chevron did not pop")
            let renamed = ["Chest day", "Back"]
            XCTAssertEqual(reading(app.routineRowLabels, becoming: renamed, within: 2), renamed)
            attach(named: "chevron-renamed")
        }
        drawerListsThree(in: app, title: title)
    }

    /// Types `name` over the pushed routine's `old` one, with no Return, so it is still being
    /// edited.
    @MainActor
    private func typeName(_ name: String, over old: String, in app: XCUIApplication) {
        let keyboard = app.keyboards.element
        XCTAssertNoThrow(try app.routineTitle.typeOver(old, with: name, keyboard: keyboard))
        XCTAssertEqual(app.routineTitle.value(becoming: name), name)
    }

    /// The new routine left untouched lists nowhere, and with four saved the drawer lists the
    /// three latest, the one made last first.
    @MainActor
    private func drawerListsThree(in app: XCUIApplication, title: XCUIElement) {
        XCTContext.runActivity(named: "An untouched new one isn't listed; the drawer has 3") { _ in
            let listedBefore = Set(app.routineRowLabels)
            XCTAssertEqual(listedBefore, ["Chest day", "Back"], "The untouched new one was listed")
            var latest = ""
            for exercise in ["Backward arm circles", "Band pull-apart, Band"] {
                app.buttons["New routine"].tap()
                XCTAssertEqual(title.value(becoming: "New routine"), "New routine")
                app.addExercise(exercise)
                let unnamed = { title.value as? String == "New routine" }
                XCTAssertFalse(reading(unnamed(), becoming: false, within: 2), "Still unnamed")
                latest = title.value as? String ?? ""
                app.navigationBars.buttons.element(boundBy: 0).tap()
                XCTAssertTrue(title.disappears(), "The chevron did not pop")
            }
            XCTAssertEqual(reading(app.routineRowLabels.count, becoming: 4, within: 2), 4)
            openDrawer(in: app)
            let listed = drawerRoutines(in: app)
            XCTAssertEqual(listed.count, 3, "The drawer lists \(listed), not the latest three")
            XCTAssertEqual(listed.first, latest, "The routine made last isn't first")
            app.drawerTitle.tap()
            XCTAssertTrue(app.drawerTitle.disappears(), "Tapping the title left the drawer open")
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

    /// The routines listed under Routines, in order: the buttons between Routines and New.
    @MainActor
    private func drawerRoutines(in app: XCUIApplication) -> [String] {
        // Read from one snapshot: buttons read one by one shift under the reading as the bars'
        // controls leave the tree, each on its own pass, after the drawer opens.
        let labels = app.snapshots { $0.elementType == .button }.map(\.label)
        guard let routines = labels.firstIndex(of: "Routines"),
              let new = labels[routines...].firstIndex(of: "New")
        else { return [] }
        return Array(labels[routines + 1 ..< new])
    }
}
