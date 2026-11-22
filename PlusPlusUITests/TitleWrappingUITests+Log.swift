import XCTest

/// Log at the largest text size, run within `testWrappedTitleAtLargestTextSize` on its way from
/// the workout the relaunch reopened to a new workout. Nothing is finished at this launch, so
/// History shows
/// its empty calendar, its line, and Go to Workouts, which the audit covers with the system's
/// segmented control and bar. How the tabs' rows look at this size is `LogSnapshotTests`'.
@MainActor
extension TitleWrappingUITests {
    /// Opens Log from the drawer, audits its empty History, and goes back to the Workouts
    /// screen by its Go to Workouts, whose way through the drawer only the running app plays.
    func logAtAX5(in app: XCUIApplication) throws {
        try XCTContext.runActivity(named: "Log at AX5 clips nothing; Go to Workouts goes") { _ in
            app.openDrawer(andTap: "Log")
            let goToWorkouts = app.buttons["log.goToWorkouts"]
            XCTAssertTrue(goToWorkouts.appears(), "Empty History showed no Go to Workouts")
            attach(named: "log-ax5")
            try app.performAccessibilityAudit(for: [.dynamicType, .textClipped])
            goToWorkouts.tap()
            // The drawer opens, its mark moves, and it closes over the list: about a second.
            XCTAssertTrue(app.drawerTitle.appears(), "Go to Workouts opened no drawer")
            XCTAssertTrue(app.drawerTitle.disappears(within: 3), "The drawer stayed open")
            XCTAssertTrue(app.buttons["New workout"].appears(), "Go to Workouts left Log")
            XCTAssertTrue(app.buttons["Menu"].exists, "Workouts came with no ++, as if pushed")
        }
    }
}
