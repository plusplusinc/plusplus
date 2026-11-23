import XCTest

/// Add exercise's muscle filter and its offers at the largest text size, run in the picker on a
/// new workout at the end of `testWorkoutAndFiltersAtLargestTextSize`, as VoiceOver reads them.
/// The parts' look at AX5 is `ExerciseListSnapshotTests`'; the reading and the sheet over the
/// picker are the app's.
@MainActor
extension TitleWrappingUITests {
    /// The buttons by their filters' names; a chip selected once chosen; the button's choice as
    /// its value, and selected; the Muscle sheet and the filtered list with Clear leading its
    /// buttons pass the audit. Clear leaves no filter on.
    func filterAtAX5(in app: XCUIApplication) throws {
        let muscle = app.buttons["Muscle"]
        XCTAssertTrue(app.buttons["Kind"].exists && app.buttons["Equipment"].exists)
        XCTAssertEqual(muscle.value as? String, "", "Muscle reads a choice with none chosen")
        muscle.tap()
        // The chip, not the bar's back button, which shares its name.
        let back = app.scrollViews.buttons["Back"]
        XCTAssertTrue(back.appears(), "Muscle opened no sheet of chips")
        // The system draws the floating sheet at about 96% of the size it lays out, so the
        // audit reads its widest words, the title and Shoulders, as clipped where they show
        // whole; anything else it finds stands. The sheet runs from its grabber, at its top
        // edge, down through its chips' scroll view, under the header.
        let chips = app.scrollViews.containing(NSPredicate(format: "label == 'Back'"))
            .firstMatch.frame.union(app.buttons["Sheet Grabber"].frame)
        try app.performAccessibilityAudit(for: [.dynamicType, .textClipped]) { issue in
            guard issue.auditType == .textClipped, let element = issue.element else { return false }
            return ["Muscle", "Shoulders"].contains(element.label) && chips.contains(element.frame)
        }
        back.tap()
        XCTAssertTrue(reading(back.isSelected, becoming: true, within: 2), "Back isn't selected")
        app.buttons["Done"].tap()
        XCTAssertTrue(back.disappears(), "Done left the chips up")
        XCTAssertEqual(muscle.value(becoming: "Back"), "Back")
        XCTAssertTrue(muscle.isSelected, "Muscle isn't selected with Back chosen")
        let clear = app.buttons["Clear filters"]
        XCTAssertTrue(clear.exists, "No Clear with the filter on")
        attach(named: "picker-filtered-ax5")
        // With the bar in view, as a sheet of chips left it at full height; flagged before any
        // filter too, and with a sheet over the bar, nothing is flagged unnamed.
        try auditBelowTheBar(in: app, unnamedChrome: true)
        clear.tap()
        XCTAssertTrue(clear.disappears(), "Clear left a filter on")
    }

    /// The results pass the audit with the offer line over them; "Filter by" reaches VoiceOver
    /// where it shows, and not where two offers leave no room for it beside their buttons, which
    /// still do. Taking an offer turns its filter on. Leaves no filter on.
    func offersAtAX5(in app: XCUIApplication) throws {
        let words = app.staticTexts["Filter by"]
        try XCTContext.runActivity(named: "The offer line at AX5 passes the audit") { _ in
            app.search(for: "arm")
            let offer = app.buttons["Add arms to Muscle"]
            XCTAssertTrue(offer.appears(), "\u{201C}arm\u{201D} offered no Arms")
            XCTAssertTrue(app.pickerRows["Backward arm circles"].exists)
            XCTAssertTrue(words.exists, "VoiceOver misses \u{201C}Filter by\u{201D} beside Arms")
            attach(named: "picker-offer-ax5")
            try app.performAccessibilityAudit(for: [.dynamicType, .textClipped])
            offer.tap()
            let clear = app.buttons["Clear filters"]
            XCTAssertTrue(clear.appears(), "Taking the offer turned no filter on")
            clear.tap()
            XCTAssertTrue(clear.disappears(), "Clear left a filter on")
        }
        XCTContext
            .runActivity(named: "Words the offer line drops at AX5 stay from VoiceOver") { _ in
                // Taking Arms emptied the field. Back and Dumbbells side by side fill the line.
                app.typeIntoSearch("back dumbbell")
                let back = app.buttons["Add back to Muscle"]
                XCTAssertTrue(back.appears(), "\u{201C}back\u{201D} offered no Back")
                XCTAssertTrue(
                    app.buttons["Add dumbbells to Equipment"].exists,
                    "No Dumbbells offer",
                )
                attach(named: "picker-two-offers-ax5")
                XCTAssertTrue(
                    words.staysAway(),
                    "VoiceOver reaches the dropped \u{201C}Filter by\u{201D}",
                )
            }
    }
}
