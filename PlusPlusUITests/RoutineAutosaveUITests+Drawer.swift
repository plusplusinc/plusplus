import XCTest

/// The ++ drawer and the Routines screen over saved routines: switching, opening counting as
/// using across a relaunch, and the drill-in from the Routines screen. Names come from the
/// muscle groups (`-fallbackNames`).
extension RoutineAutosaveUITests {
    /// From a new routine with nothing saved, two routines made, switched between, and opened
    /// from the Routines screen.
    @MainActor
    func drawerSwitchesRoutines(in app: XCUIApplication, title: XCUIElement) {
        XCTContext.runActivity(named: "The drawer marks the routine showing, and New") { _ in
            app.addExercise("Barbell bench press, Barbell, bench")
            XCTAssertEqual(title.value(becoming: "Chest"), "Chest")
            openDrawer(in: app)
            XCTAssertEqual(drawerRoutines(in: app), ["Chest"])
            XCTAssertTrue(app.buttons["Chest"].isSelected, "The routine showing isn't marked")
            XCTAssertFalse(app.buttons["Routines"].isSelected)
            attach(named: "drawer-routine")
            app.buttons["New routine"].tap()
            XCTAssertTrue(app.drawerTitle.disappears(), "New did not close the drawer")
            XCTAssertEqual(title.value(becoming: "New routine"), "New routine")
            XCTAssertEqual(app.exerciseRows.count, 0)
            openDrawer(in: app)
            XCTAssertTrue(app.buttons["New routine"].isSelected, "New isn't marked on a new one")
            XCTAssertFalse(app.buttons["Chest"].isSelected)
            // On an untouched new routine, New only closes the drawer.
            app.buttons["New routine"].tap()
            XCTAssertTrue(app.drawerTitle.disappears(), "New did not close the drawer")
            XCTAssertEqual(title.value as? String, "New routine")
        }
        XCTContext.runActivity(named: "Switching keeps both, and opening counts as using") { _ in
            app.addExercise("Pull-up, Pull-up bar", searching: "pull-up")
            XCTAssertEqual(title.value(becoming: "Back"), "Back")
            openDrawer(in: app)
            XCTAssertEqual(drawerRoutines(in: app), ["Back", "Chest"])
            app.buttons["Chest"].tap()
            XCTAssertTrue(app.drawerTitle.disappears(), "Opening a routine left the drawer open")
            XCTAssertEqual(title.value(becoming: "Chest"), "Chest")
            XCTAssertEqual(app.exerciseNames, ["Barbell bench press"])
            app.relaunch()
            XCTAssertEqual(title.value as? String, "Chest", "Launch didn't reopen the one opened")
            openDrawer(in: app)
            XCTAssertEqual(drawerRoutines(in: app), ["Chest", "Back"])
        }
        routinesScreenDrillsIn(in: app, title: title)
    }

    /// The Routines screen lists every routine, latest first; a row or + pushes a routine with a
    /// back chevron in place of ++, which the chevron or an edge swipe pops.
    @MainActor
    private func routinesScreenDrillsIn(in app: XCUIApplication, title: XCUIElement) {
        XCTContext.runActivity(named: "Routines lists every routine, and a row drills in") { _ in
            app.buttons["Routines"].tap()
            XCTAssertTrue(app.drawerTitle.disappears(), "Routines did not close the drawer")
            let rows = app.buttons.matching(identifier: "routines.row")
            XCTAssertEqual(
                reading(rows.allElementsBoundByIndex.map(\.label), becoming: ["Chest", "Back"], within: 2),
                ["Chest", "Back"],
            )
            attach(named: "routines-screen")
            openDrawer(in: app)
            XCTAssertTrue(app.buttons["Routines"].isSelected, "Routines isn't marked")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            XCTAssertTrue(app.drawerTitle.disappears(), "A tap on the sliver left it open")
            rows.element(boundBy: 1).tap()
            XCTAssertEqual(title.value(becoming: "Back"), "Back", "The row pushed no routine")
            XCTAssertFalse(app.buttons["Menu"].exists, "++ shows on a pushed routine")
            attach(named: "pushed-routine")
            edgeSwipe(in: app)
            XCTAssertTrue(title.disappears(), "The edge swipe did not pop")
            XCTAssertFalse(app.drawerTitle.exists, "The edge swipe opened the drawer")
            XCTAssertTrue(app.buttons["Menu"].appears(), "No ++ back on the Routines screen")
        }
        XCTContext.runActivity(named: "+ pushes a new routine, and the chevron pops it") { _ in
            app.buttons["New routine"].tap()
            XCTAssertEqual(title.value(becoming: "New routine"), "New routine")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(title.disappears(), "The chevron did not pop")
            edgeSwipe(in: app)
            XCTAssertTrue(app.drawerTitle.appears(), "The edge swipe on Routines did not open it")
            app.drawerTitle.tap()
            XCTAssertTrue(app.drawerTitle.disappears(), "Tapping the title left the drawer open")
        }
    }

    @MainActor
    private func openDrawer(in app: XCUIApplication) {
        app.buttons["Menu"].tap()
        XCTAssertTrue(app.drawerTitle.appears(), "++ did not open the drawer")
    }

    /// The routines listed under Routines, in order: the buttons between Routines and New.
    @MainActor
    private func drawerRoutines(in app: XCUIApplication) -> [String] {
        let labels = app.buttons.allElementsBoundByIndex.map(\.label)
        guard let routines = labels.firstIndex(of: "Routines"),
              let new = labels[routines...].firstIndex(of: "New routine")
        else { return [] }
        return Array(labels[routines + 1 ..< new])
    }

    @MainActor
    private func edgeSwipe(in app: XCUIApplication) {
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 2, dy: 0))
        edge.press(
            forDuration: 0.05,
            thenDragTo: edge.withOffset(CGVector(dx: 300, dy: 0)),
            withVelocity: .default,
            thenHoldForDuration: 0,
        )
    }
}
