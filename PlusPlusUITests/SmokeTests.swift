import XCTest

/// End-to-end smoke tests for the core flows, run on the CI simulator.
/// Screenshots are attached at key points and exported as workflow
/// artifacts, standing in for hands-on validation between Mac sessions.
/// The app launches with --uitest-reset (in-memory store, seed data only).
final class SmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitest-reset"]
        launchAndSettle()
    }

    /// Launch and confirm the app is actually interactive before the test
    /// body runs. `app.launch()` on a loaded CI runner intermittently returns
    /// with the process up but the first screen not yet live — the documented
    /// launch-wedge flake: the tab bar never materialises and the test's first
    /// assertion times out ~2 minutes in. The `--uitest-reset` launch lands on
    /// the Today tab, so use the tab bar as the ready signal; if it doesn't
    /// appear, terminate and relaunch once. No assertion here — if it wedges
    /// twice, let the test's own first assertion surface it rather than mask a
    /// genuine startup crash behind a passing setUp.
    private func launchAndSettle() {
        for attempt in 0..<2 {
            app.launch()
            if tabButton("today").waitForExistence(timeout: 30) { return }
            if attempt == 0 { app.terminate() }
        }
    }

    /// The chrome is the system's `TabView` bar, carrying Today · Browse ·
    /// Search (2026-08-05). Browse and the search tab show the same screen;
    /// the scope control in their navigation bar picks the catalog.
    private func tabButton(_ tab: String) -> XCUIElement {
        app.tabBars.buttons[tab.capitalized]
    }

    /// Go to a catalog: the Browse tab, then the scope control. The same control
    /// does the same job while searching (`selectScope`).
    private func goToCatalog(_ scope: String) {
        let key = tabButton("browse")
        XCTAssertTrue(key.waitForExistence(timeout: 10), "the Browse tab is in the bar")
        key.tap()
        selectScope(scope)
    }

    /// The NATIVE search field, expanded out of the search-role tab — a
    /// `searchField` element, not a custom `textField` with an identifier.
    private var searchField: XCUIElement {
        app.searchFields.firstMatch
    }

    /// Open the catalogs (the separated search circle beside Today), which
    /// morphs the bar into the field.
    private func openSearch() {
        let key = app.tabBars.buttons["Search"]
        XCTAssertTrue(key.waitForExistence(timeout: 10))
        key.tap()
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
    }

    /// Pick a catalog on the scope control in the catalog roots' navigation
    /// bar (`ScopeSegmentedControl`, 2026-08-06 — the app-drawn segmented
    /// control in the raised-key family that replaced the scope wheel; cells
    /// keep the wheel's identifiers).
    ///
    /// ⚠️ Identifiers are per-INSTANCE (`-browse` / `-search`): both catalog
    /// roots stay mounted over one shared scope, and an inactive tab's
    /// elements are visible to queries, so a bare identifier is a
    /// multiple-match once both tabs have been built.
    ///
    /// Every segment is on screen at once — the control divides the row it is
    /// given, it does not scroll — so there is no realized-but-clipped cell
    /// and no swipe to reach one (the wheel's track fallback died with it). A
    /// tap on the already-selected cell is a no-op write, so callers don't
    /// need to check state first.
    private func selectScope(_ scope: String, on instance: String = "browse") {
        let cell = app.buttons["findScope-\(scope.lowercased())-\(instance)"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "the scope control rides the catalog roots' bar")
        cell.tap()
    }

    // MARK: - Flows

    func testBuildRoutineWithExerciseAndWeight() throws {
        createRoutine(named: "Push Day")
        addExercise(searching: "Bench Press")

        // The exercise appears as a rail row; tapping it opens the
        // planning sheet where metrics are edited (v2 design).
        let row = app.staticTexts["Bench Press"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        // First increment lands on the 45 lb default. The value renders
        // as a tappable button (it opens the wheel picker); since the
        // VoiceOver pass the number is the button's accessibility VALUE
        // (its label is the metric name, "Weight"), so assert on the value.
        let increment = app.buttons["weightIncrement"]
        XCTAssertTrue(increment.waitForExistence(timeout: 5))
        let weightValue = app.buttons["weightValue"]
        increment.tap()
        XCTAssertTrue(waitForValue(weightValue, "45 lb"), "first increment lands on the empty-bar default")
        increment.tap()
        XCTAssertTrue(waitForValue(weightValue, "50 lb"), "second increment steps by 5 lb")

        snap("exercise-sheet")

        app.buttons["closeExerciseSheet"].tap()
        XCTAssertTrue(app.buttons["startWorkoutButton"].waitForExistence(timeout: 5))
        snap("routine-detail")
    }

    /// The swipe-reveal contract, on CI at last (builds 17/31/33 all
    /// reported "snaps back on release" and no test exercised it):
    /// a slow pull with a momentum-free lift must leave the actions
    /// revealed and TAPPABLE; a tap while open must CLOSE the row (not
    /// navigate); the tapped action must actually run. Pre-fix, row
    /// content activated on touch-up-inside, so the reveal drag's own
    /// finger-lift ran the tap-close branch and shut the row — this
    /// test rejected the first, slop-based fix attempt (movement
    /// relative to a row that chases the finger is ~zero), which is
    /// why activation is now composed exclusively with the drag.
    func testSwipeRevealActionSurvivesRelease() throws {
        createRoutine(named: "Swipe Target")

        // Back to the library list — the swipe surface under test. Since
        // #848 blank creation REPLACES the catalog with the detail on the
        // library root (so a delete from the new routine returns to the
        // library, not the catalog), a single Back returns straight to the
        // list — there is no intermediate catalog to step through.
        tapBack("routine detail")

        let card = app.staticTexts["Swipe Target"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        let delete = app.buttons["DELETE"]

        // 1. The reveal the device kept reporting broken: a slow pull well
        // past halfway with a momentum-free lift — the exact gentle release
        // that historically snapped shut. `revealDelete` drags and waits for
        // the action to land HITTABLE, re-dragging only to absorb the
        // runner's gesture jitter (see the helper). This does NOT soften the
        // regression guard: a real close-on-release bug is deterministic —
        // it shuts the row on every attempt, so the action never becomes
        // hittable and this fails — and step 2 below is an independent
        // backstop (a closed row navigates on tap).
        XCTAssertTrue(revealDelete(start, delete), "actions must stay revealed and tappable after a gentle release")
        snap("swipe-revealed-after-release")

        // 2. A tap while open closes the row — and must NOT navigate
        // (isHittable is documented false for nonexistent elements, so
        // the predicate is safe whether the closed action is pruned
        // from the tree or merely unhittable).
        // ⚠️ Tap an ABSOLUTE point between the screen's edge and DELETE, not a
        // normalized offset into the row. The instrumented run gave the reason
        // outright: with the swipe open the cell's frame is
        // `(-92,154 420x69)` — it has slid 92 pt LEFT, so its leading fifth is
        // off the display and a `dx: 0.15` tap landed at x = -29, on nothing
        // at all. Every earlier round tapped into that dead zone and read the
        // silence as "the row ignored it".
        //
        // Half of DELETE's own minX is inside the visible row content and
        // clear of the revealed actions, whatever the shift happens to be.
        let row = app.cells.containing(.staticText, identifier: "Swipe Target").firstMatch
        let rowTarget = row.exists ? row : card
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: delete.frame.minX / 2, dy: rowTarget.frame.midY))
            .tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == 0"), object: delete)
        // ⚠️ The generic inventory is useless here — it returns the tab bar,
        // not the row. This reports the geometry instead, which is what tells
        // "the row ignored the tap" apart from "the tap landed somewhere
        // else": where DELETE is, where the tap went, and whether we ended up
        // inside the routine.
        XCTAssertEqual(
            XCTWaiter().wait(for: [closed], timeout: 3),
            .completed,
            """
            a tap while open must close the row · \
            DELETE \(rect(delete.frame)) hittable=\(delete.isHittable) · \
            tapped \(row.exists ? "cell" : "label") \(rect(rowTarget.frame)) · \
            navigated=\(app.buttons["addExerciseButton"].exists)
            """
        )
        XCTAssertFalse(
            app.buttons["addExerciseButton"].waitForExistence(timeout: 3),
            "a tap while open must close, not navigate into the routine"
        )

        // Discriminator for the step-3 CI failures (2 runs, retry
        // included): if step 2's tap actually NAVIGATED (a zoom push
        // slower than the 3 s negative window), we're on the detail
        // screen — whose title also matches `card` — and no drag can
        // ever reveal. Pin the surface before dragging again.
        XCTAssertTrue(
            app.buttons["newRoutineButton"].exists,
            "must still be on the routine list before the re-reveal"
        )

        // 3. Re-reveal and run the action: the routine is deleted. Same
        // drag-and-wait as step 1 (step 1 already proved reveal-survives-
        // release); here we just need the action hittable so we can tap it.
        XCTAssertTrue(revealDelete(start, delete), "the DELETE action must reveal and become hittable on re-reveal")
        delete.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == 0"), object: card)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "DELETE must remove the routine")
    }

    /// The Routines-tab catalog path specifically: template detail must
    /// open from THIS stack, not just Today's setup step. Build 33
    /// shipped with the RoutineTemplate destination registered inside
    /// the pushed catalog screen — Today's path resolved it, the
    /// Routines tab hit SwiftUI's missing-destination placeholder.
    /// The leading (swipe-right) quick-add on the equipment catalog
    /// (2026-07-17): a rightward drag reveals ADD, tapping it joins the
    /// gear to the kit — visible in the setup Done bar's live count.
    /// Same jitter-absorbing shape as `revealDelete`, mirrored: a
    /// deterministic leading-reveal bug fails every attempt.
    func testEquipmentQuickAddLeadingSwipe() throws {
        app.terminate()
        app.launchArguments += ["--uitest-onboarding"]
        app.launch()

        let equipCTA = app.buttons["setupEquipmentStep"]
        XCTAssertTrue(equipCTA.waitForExistence(timeout: 10))
        equipCTA.tap()

        let setEquipment = app.buttons["setEquipmentButton"]
        XCTAssertTrue(setEquipment.waitForExistence(timeout: 5))
        XCTAssertEqual(setEquipment.label, "Done · bodyweight only", "fresh store starts gearless")

        // Black-box test of the leading quick-add. The revealed ADD
        // button lives BELOW content in the row's ZStack, opacity- and
        // hit-test-gated; XCUITest never surfaces it in the a11y tree
        // even when revealed (CI-proven across six runs: the row slides
        // open — the card's frame shifts +58 — yet the button element
        // reads exists=false). So we don't query the button. Instead:
        // (1) drag the row right and confirm the reveal by the card's
        // frame delta (the offset the reveal produces IS observable),
        // then (2) tap the now-uncovered left region by coordinate — a
        // synthetic touch dispatches through UIKit hit-testing, not the
        // a11y tree, so it reaches the revealed ADD that queries can't
        // see — and (3) assert the real outcome: the Done bar's count.
        //
        // Alphabetically-first cards, first-screen-realized (#222 rule).
        // Drags start from the row's MIDDLE: within 44 pt of the screen
        // edge the narrowed back-swipe owns rightward drags by design,
        // so an edge-adjacent start would hand the touch to the pop.
        var revealedCard: XCUIElement?
        var attempts: [String] = []
        for name in ["Ab Crunch Machine", "Ab Wheel"] where revealedCard == nil {
            let card = app.staticTexts[name]
            XCTAssertTrue(card.waitForExistence(timeout: 5), "missing card \(name)")
            for form in ["slowDrag", "slowDrag", "swipeRight"] where revealedCard == nil {
                let before = card.frame.minX
                if form == "slowDrag" {
                    let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    start.press(
                        forDuration: 0.05,
                        thenDragTo: start.withOffset(CGVector(dx: 150, dy: 0)),
                        withVelocity: .slow,
                        thenHoldForDuration: 0.4
                    )
                } else {
                    card.swipeRight()
                }
                // A ≥40 pt rightward shift = the leading edge revealed
                // (full open is +58; the threshold absorbs mid-commit
                // and runner jitter). An unmoved frame = the drag never
                // reached the reveal gesture.
                let shifted = card.frame.minX - before
                attempts.append("\(name)/\(form): Δx=\(Int(shifted))")
                if shifted >= 40 { revealedCard = card }
            }
        }
        guard let card = revealedCard else {
            snap("quick-add-failed")
            return XCTFail("leading reveal never opened the row — \(attempts.joined(separator: " · "))")
        }
        snap("equipment-quick-add-revealed")

        // Tap the revealed ADD: it occupies the leftmost 58 pt of the
        // row after the reveal, and content (opaque) has slid clear of
        // it. Absolute window coordinate at the row's vertical center,
        // x=28 (safely inside the 58 pt ADD block past any list inset).
        let addPoint = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 28, dy: card.frame.midY))
        addPoint.tap()

        // Membership landed: the Done bar's count is the real assertion.
        XCTAssertTrue(waitForLabel(setEquipment, "Done · 1 item"),
                      "quick add should join the gear to the kit — reveal path: \(attempts.joined(separator: " · "))")
    }

    private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        return XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: timeout
        ) == .completed
    }

    func testRoutinesCatalogOpensTemplateDetail() throws {
        goToCatalog("routines")

        // The catalog already lists the templates under CATALOG, so
        // reaching one is just search narrowing the list you're on — no
        // detour through another surface (2026-07-25). Search also PINS the
        // row (the lazy-List rule); a bodyweight template survives a
        // zero-equipment store, so don't swap in a gear-requiring one.
        let plus = app.buttons["newRoutineButton"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        openSearch()

        let field = searchField
        field.tap()
        field.typeText("Bodyweight Basics")
        let templateRow = app.staticTexts["Bodyweight Basics"]
        XCTAssertTrue(templateRow.waitForExistence(timeout: 5))
        templateRow.tap()

        // The detail screen, not the triangle: Add is its primary action.
        XCTAssertTrue(app.buttons["addTemplateButton"].waitForExistence(timeout: 5))
        snap("routines-tab-template-detail")

        // Back returns to the RESULTS with the query intact — search is
        // a stack, not a modal (decision A's round-trip promise).
        tapBack("template detail")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Bodyweight Basics")

        // The native field's own Cancel clears the query; the catalog stays
        // put, since the SCOPE — not the field — decides which one you're on.
        // ⚠️ It is labelled **Close**, beside a "Clear text" key. The
        // affordance is the SYSTEM's — the field is morphed out of the
        // search-role tab — so its noun is not the app's to choose, and
        // "Cancel" stopped matching when #452 reworked this surface. Both
        // are accepted: the assertion is about leaving search, not about
        // which word the platform picked.
        let cancel = app.buttons
            .matching(NSPredicate(format: "label IN {'Cancel', 'Close'} OR identifier IN {'Cancel', 'Close'}"))
            .firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "the search field's own Close · \(buttonInventory())")
        cancel.tap()
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "cancelling search returns the catalog · \(buttonInventory())")
    }

    /// The universal surface end to end: open search from the bar, dial the
    /// control to the Exercises scope, create a custom from the query, and land
    /// on Browse showing the exercises catalog with the new row present (the
    /// no-toasts landing grammar).
    func testUniversalSearchCreatesExercise() throws {
        openSearch()
        snap("find-or-create-open")

        // While searching, the catalog is picked on the scope control rather
        // than by leaving search — the SEARCH instance's control.
        selectScope("exercises", on: "search")
        let createRow = app.buttons["createExerciseRow"]
        XCTAssertTrue(createRow.waitForExistence(timeout: 5))

        // The query prefills the editor (the create-from-here contract).
        let field = searchField
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Wall Slides")
        createRow.tap()

        let nameField = app.textFields["exerciseNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertEqual(nameField.value as? String, "Wall Slides")
        app.buttons["saveExerciseButton"].tap()

        // Lands on Browse, dialled to exercises (create → its list, entrance
        // flash; the landing writes the shared scope). Do NOT probe the
        // catalog's top create row here: the arrival beat scrolls the new
        // W-named row to center, which pushes the top of the lazy List out of
        // the realized window — unrealized rows are invisible to XCUITest
        // (the testing.md lazy-list law; this assertion's first form failed
        // CI exactly that way). The tab item's selection, the scope cell's
        // `.isSelected`, and the scrolled-into-view row are the honest probes.
        let browseTab = tabButton("browse")
        XCTAssertTrue(browseTab.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Wall Slides"].waitForExistence(timeout: 5))
        XCTAssertTrue(browseTab.isSelected)
        XCTAssertTrue(app.buttons["findScope-exercises-browse"].isSelected, "the scope control landed on the exercises catalog")
        snap("find-or-create-landed-exercise")
    }

    func testCreateCustomExerciseWithNotes() throws {
        // Not "PT": typeText with two consecutive shifted characters is a
        // known flake on slow simulators (the second shift can drop).
        createRoutine(named: "Rehab")

        app.buttons["addExerciseButton"].tap()
        let newButton = app.buttons["newExerciseButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))
        newButton.tap()

        let nameField = app.textFields["exerciseNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Band Pulses")

        snap("exercise-editor")

        app.buttons["saveExerciseButton"].tap()

        // Creating a custom exercise in the routine picker adds it STRAIGHT to
        // the routine and pops back (2026-07-19) — no return to the picker, no
        // second tap. Prove we actually landed on the routine detail: the
        // routine's own Add button is back and the picker's create row is gone
        // (asserting only that "Band Pulses" exists would pass even stranded on
        // the picker, where it also shows as a row — swift-reviewer catch).
        XCTAssertTrue(app.buttons["addExerciseButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["newExerciseButton"].exists)
        XCTAssertTrue(app.staticTexts["Band Pulses"].waitForExistence(timeout: 5))
        snap("custom-exercise-in-routine")
    }

    /// The mascot form demo: the FORM card renders on the exercise sheet
    /// and expands into the demo sheet. Under --uitest-reset the mascot
    /// is deliberately frozen (static pose, no render-loop motion), so
    /// this also proves the app's first RealityKit viewport initializes
    /// on a CI simulator without starving XCUITest's quiescence wait —
    /// and the screenshots are the only mascot visuals reviewable from a
    /// remote session.
    func testExerciseSheetShowsFormDemo() throws {
        // Deadlift, not Squat: the picker's List is lazy and the exact
        // "Squat" row sorts below its many variants (Bulgarian Split,
        // Front, Goblet...) — off the first screen, invisible to
        // XCUITest (the testing.md lazy-list law; #222). "Deadlift"
        // sorts first in its own filtered list.
        createRoutine(named: "Leg Day")
        addExercise(searching: "Deadlift")

        let row = app.staticTexts["Deadlift"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        // ScrollView content is fully realized (not List-lazy), so
        // existence is immediate; scroll only to make it tappable.
        let card = app.buttons["mascotPreviewCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        if !card.isHittable {
            app.swipeUp()
        }
        snap("exercise-sheet-form-card")
        card.tap()

        let close = app.buttons["closeMascotDemoSheet"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        snap("mascot-demo-sheet")
        close.tap()

        let closeSheet = app.buttons["closeExerciseSheet"]
        XCTAssertTrue(closeSheet.waitForExistence(timeout: 5))
        closeSheet.tap()
        XCTAssertTrue(app.buttons["startWorkoutButton"].waitForExistence(timeout: 5))
    }

    /// The facet row (filtering returns, 2026-07-31; multi-select trays
    /// #498): the muscle chip opens a tray, picking Chest narrows the
    /// Exercises catalog, the summary chip appears, and Clear all
    /// restores the full list. First-screen elements only (the lazy-list
    /// law) — and --uitest-reset PRE-FILLS the kit (`populateLibrary`),
    /// so everything is doable and the narrowed run is alphabetical from
    /// the top: assert early-alphabet rows ("Bench Press" under Chest,
    /// "Arm Circles" after clearing), never a P-row (an early run of
    /// this test failed exactly there).
    func testExerciseFilterNarrowsAndClears() throws {
        goToCatalog("exercises")

        let muscleChip = app.buttons["facetMuscle"]
        XCTAssertTrue(muscleChip.waitForExistence(timeout: 10), "the facet row rides the catalog")
        muscleChip.tap()
        // A multi-select facet is a LIST in a tray, keyed by raw value.
        let chest = app.buttons["pick-chest"]
        XCTAssertTrue(chest.waitForExistence(timeout: 5), "the muscle tray offers Chest")
        chest.tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "the tray closes on Done")
        done.tap()

        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 5), "a chest row survives the filter")
        snap("exercise-filter-chest")

        let summary = app.buttons["filterSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "active filters summarize")
        summary.tap()
        let clearAll = app.buttons["clearAllFilters"]
        XCTAssertTrue(clearAll.waitForExistence(timeout: 5), "the summary popover holds Clear all")
        clearAll.tap()

        // A non-chest row near the top of the full run proves the clear.
        XCTAssertTrue(app.staticTexts["Arm Circles"].waitForExistence(timeout: 5), "clearing restores the whole catalog")
        XCTAssertFalse(summary.exists, "the summary chip leaves with the filters")
    }

    func testExecuteWorkoutAndSeeHistory() throws {
        createRoutine(named: "Quick Session")
        addExercise(searching: "Push-Up")

        app.buttons["startWorkoutButton"].tap()

        // 3 sets (default): complete each, skipping the rest countdown.
        for setIndex in 1...3 {
            let complete = app.buttons["completeSetButton"]
            XCTAssertTrue(complete.waitForExistence(timeout: 10), "Set \(setIndex) screen should appear")
            if setIndex == 1 {
                snap("set-logging")
            }
            complete.tap()

            if setIndex < 3 {
                skipRest(afterSet: setIndex)
            }
        }

        XCTAssertTrue(app.staticTexts["Workout Complete"].waitForExistence(timeout: 5))
        snap("routine-complete")
        app.buttons["sessionDoneButton"].tap()

        // Closing the recap lands on Today on its own (the recap-close
        // flow: the root switches to Today and the just-finished card
        // converts to done). The workout started from a routine detail
        // in the routines catalog, yet the record is right here — no back-out,
        // no manual tab hop. The anytime card's quick-start edit key is a
        // Today-only element (routine detail has none), and the landing
        // seats the anytime row at the top, so its presence proves the
        // auto-landing.
        XCTAssertTrue(
            app.buttons["quickStartEditButton"].waitForExistence(timeout: 10),
            "closing the recap must land on the Today screen"
        )

        // Snapshot the list before asserting, so a failure here leaves
        // visual evidence of what history actually showed.
        snap("history-list")

        // Generous timeouts: on a loaded CI simulator, the first snapshot
        // after navigation can take most of a minute to evaluate.
        XCTAssertTrue(app.staticTexts["Quick Session"].waitForExistence(timeout: 30))
        // ⚠️ Tap the CARD, not its title. The committed card is a
        // `NavigationLink` whose label is the whole row, and Today prints the
        // routine's name more than once — the card, and the "Routine created"
        // entry under it. Tapping the bare text resolved to one that goes
        // nowhere, and the test then sat on Today waiting for a record it had
        // never opened.
        let recordCard = app.buttons["committedSessionCard"].firstMatch
        XCTAssertTrue(
            recordCard.waitForExistence(timeout: 10),
            "the committed card on Today · \(buttonInventory())"
        )
        // ⚠️ TWO floating bars, and the card has to clear both. The
        // navigation bar sits over the top of the timeline and the tab bar
        // over the bottom; XCUITest models neither as covering, so a card
        // under either reports hittable and the tap lands on the bar. Dave
        // confirmed on build 158 that tapping a finished workout opens its
        // record, so the app was never the problem — the probe kept aiming at
        // covered points. It has been found under each bar in turn: below the
        // fold while the setup scaffold held a full viewport, then at y = 52
        // of a 912 pt screen, tucked under the large title, after zero
        // scrolls.
        //
        // So scroll toward whichever band it is in, rather than assuming the
        // fold is always the problem, and stop when it is clear of both.
        let bandHeight: CGFloat = 140
        var scrolls = 0
        while scrolls < 8 {
            let frame = recordCard.frame
            let clearsTop = frame.minY > bandHeight
            let clearsBottom = frame.maxY < app.frame.height - bandHeight
            if recordCard.isHittable, clearsTop, clearsBottom { break }
            if clearsTop { app.swipeUp() } else { app.swipeDown() }
            scrolls += 1
        }
        // The record lists one row per logged set. Push-Up is equipment-free
        // weight/reps, so it derives to strength and the row's noun is "Set" —
        // the work-unit vocabulary does not rewrite this one.
        //
        // ⚠️ It depends on THREE sets, not just on the noun: a record row
        // wears no label at all when its block holds one (the count-of-one
        // rule). Drop this flow to a single set and the assertion is looking
        // for a string the app is right not to print.
        //
        // ⚠️ By absolute coordinate, the same dispatch the swipe row needed:
        // an element tap goes through accessibility, and every one of those
        // this flow tried was swallowed.
        let setRow = app.staticTexts["Set 1"]
        let card = recordCard.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: card.midX, dy: card.midY))
            .tap()
        snap("history-detail")
        XCTAssertTrue(
            setRow.waitForExistence(timeout: 15),
            """
            the record lists the logged sets · \
            card \(rect(card)) in screen \(rect(app.frame)) after \(scrolls) scrolls · \
            \(textInventory(6))
            """
        )
    }

    /// #503's exit-door regression: the dialog's Finish used to dismiss
    /// instantly — no recap, and no finish notification, so Today never
    /// landed or converted the card. Every finish door goes through the
    /// recap now, and Continue is the ONE place the landing posts, so
    /// reaching Today at the end proves the notification fired for this
    /// door too.
    func testEarlyFinishRoutesThroughRecap() throws {
        createRoutine(named: "Early Out")
        addExercise(searching: "Push-Up")

        app.buttons["startWorkoutButton"].tap()

        // Log ONE of the three sets, then end early from the HUD.
        let complete = app.buttons["completeSetButton"]
        XCTAssertTrue(complete.waitForExistence(timeout: 10), "the first set screen")
        complete.tap()
        skipRest(afterSet: 1)

        let end = app.buttons["End workout"]
        XCTAssertTrue(end.waitForExistence(timeout: 5), "the HUD's End key")
        end.tap()
        let finish = app.buttons["Finish workout"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5), "the exit dialog offers Finish with sets logged")
        finish.tap()

        XCTAssertTrue(
            app.staticTexts["Workout Complete"].waitForExistence(timeout: 5),
            "the exit dialog's Finish shows the recap, like every other finish door (#503)"
        )
        snap("early-finish-recap")
        app.buttons["sessionDoneButton"].tap()

        XCTAssertTrue(
            app.buttons["quickStartEditButton"].waitForExistence(timeout: 10),
            "closing the recap lands on Today — the landing this door used to skip"
        )
    }

    /// Regression for the third-strike scroll bug: with enough exercises
    /// to overflow the screen, the detail list must actually scroll (the
    /// long-press rail gestures used to starve the scroll pan).
    func testDetailListScrollsWhenOverflowing() throws {
        app.terminate()
        app.launchArguments += ["--uitest-bigworkout"]
        app.launch()

        goToCatalog("routines")

        let card = app.staticTexts["Big Day"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        let addRow = app.buttons["addExerciseButton"]
        XCTAssertTrue(addRow.waitForExistence(timeout: 5), "add row is in the hierarchy even while offscreen")
        XCTAssertFalse(addRow.isHittable, "16 rows must overflow — otherwise this test can't prove scrolling")
        snap("overflow-top")

        // Swipe on the rows themselves, where a thumb naturally lands.
        for _ in 0..<4 where !addRow.isHittable {
            app.swipeUp()
        }

        snap("overflow-after-scroll")
        XCTAssertTrue(addRow.isHittable, "the add-exercise row at the bottom of the rail must be reachable by scrolling")
    }

    /// The setup-as-timeline onboarding: a fresh install's Today shows
    /// three gated setup entries; completing them bottom-up commits each
    /// to the rail and stages the first real routine.
    func testSetupTimelineOnboarding() throws {
        app.terminate()
        app.launchArguments += ["--uitest-onboarding"]
        app.launch()

        // Fresh install: equipment is the only ready step; the ones
        // above it are gated.
        let equipCTA = app.buttons["setupEquipmentStep"]
        XCTAssertTrue(equipCTA.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Needs your equipment first"].exists)
        snap("setup-fresh")
        equipCTA.tap()

        // Step 1: the real catalog in setup mode (v4 SSF) — the preset
        // strip died (#203), and the toggle rows died with the card
        // rebuild (2026-07-17): a row now pushes the gear's DETAIL,
        // where "Add to kit" is the membership write. A fresh store
        // owns NOTHING (#232) — ownership is opt-in, so pick the way
        // users do: open a card, add it, come back, keep moving.
        // First-screen rows only (lazy List rows below the fold aren't
        // realized) — the two alphabetically-FIRST catalog names, so
        // catalog growth can't push them under the fold (#222).
        let setEquipment = app.buttons["setEquipmentButton"]
        XCTAssertTrue(setEquipment.waitForExistence(timeout: 5))
        for name in ["Ab Crunch Machine", "Ab Wheel"] {
            let card = app.otherElements["equipmentCard-\(name)"].firstMatch
            let fallback = app.staticTexts[name].firstMatch
            let row = card.waitForExistence(timeout: 2) ? card : fallback
            XCTAssertTrue(row.waitForExistence(timeout: 5), "missing equipment card for \(name)")
            row.tap()
            // Add to kit is a prominent card whose whole surface is the tap
            // target (2026-07-18); the switch stays the identified control.
            let add = app.switches["addToMyEquipment"]
            XCTAssertTrue(add.waitForExistence(timeout: 5), "\(name) detail should show the kit toggle")
            if (add.value as? String) != "1" { add.tap() }
            XCTAssertTrue(waitForValue(add, "1"), "adding \(name) should flip the kit toggle on")
            tapBack("\(name) detail")
            XCTAssertTrue(setEquipment.waitForExistence(timeout: 5), "back from \(name) detail should land on the catalog")
        }
        setEquipment.tap()
        // The populate offer is gone (2026-07-17): the exercise catalog
        // is always fully visible, so equipment Done goes straight on to
        // step 2 with content already available downstream.

        // Step 2 unlocks: pick a routine. The step lands on Browse dialled to
        // the routine catalog (2026-07-25; tabs collapsed 2026-08-05) — yours,
        // then everything you could add. This exercises search + Add end to end.
        let routineCTA = app.buttons["setupRoutineStep"]
        XCTAssertTrue(routineCTA.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Equipment set"].waitForExistence(timeout: 5))
        snap("setup-step2")
        routineCTA.tap()

        // Search pins the template regardless of catalog growth (the
        // lazy-List rule: only realized rows exist).
        XCTAssertTrue(app.buttons["newRoutineButton"].waitForExistence(timeout: 10))
        openSearch()
        let field = searchField
        field.tap()
        field.typeText("Bodyweight Basics")
        let templateRow = app.staticTexts["Bodyweight Basics"]
        XCTAssertTrue(templateRow.waitForExistence(timeout: 5))
        templateRow.tap()
        let add = app.buttons["addTemplateButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()

        // ONE landing for every template add (design review 2026-07-23):
        // the add lands on the routines catalog and entrance-flashes the
        // new card — same as adding from that catalog itself. The
        // card is briefly held out for its entrance beat, so wait
        // generously. Setup then continues back on Today.
        let landedCard = app.staticTexts["Bodyweight Basics"]
        XCTAssertTrue(
            landedCard.waitForExistence(timeout: 10),
            "the template add should land on the Routines list showing the new card"
        )
        snap("setup-step2-added")
        tabButton("today").tap()

        // Step 3 unlocks: schedule Bodyweight Basics for today so it stages.
        let scheduleCTA = app.buttons["setupScheduleStep"]
        XCTAssertTrue(scheduleCTA.waitForExistence(timeout: 10))
        snap("setup-step3")
        scheduleCTA.tap()

        // Scheduling lives in its own tray now (#429): the pushed settings
        // page shows a Schedule row that opens it, and a view-only tray
        // dismisses with the Done text key.
        //
        // ⚠️ The mode is no longer a segment. #445 retired the custom
        // `SegmentedTabs` control, and multi-word modes moved to a
        // `NavigationSelectRow` — a row showing the current mode that PUSHES
        // the option list (a segmented control truncates three phrases). So
        // reaching "Days of the week" is two taps: open the row, pick the
        // option. Picking dismisses the pushed screen itself.
        let scheduleRow = app.buttons["scheduleRow"]
        XCTAssertTrue(scheduleRow.waitForExistence(timeout: 5))
        scheduleRow.tap()

        let modeRow = app.buttons["scheduleModeRow"]
        XCTAssertTrue(modeRow.waitForExistence(timeout: 5), "the schedule tray's mode row · \(buttonInventory())")
        modeRow.tap()
        let daysOption = app.buttons["Days of the week"]
        XCTAssertTrue(daysOption.waitForExistence(timeout: 5), "the pushed mode list · \(buttonInventory())")
        daysOption.tap()

        let weekday = Calendar.current.component(.weekday, from: Date())
        let dayChip = app.buttons["scheduleDay\(weekday)"]
        XCTAssertTrue(dayChip.waitForExistence(timeout: 5), "picking weekdays reveals the day chips · \(buttonInventory())")
        dayChip.tap()
        app.buttons["Done"].tap()
        // Then pop routine settings back to Today.
        tapBack("routine settings")

        // Scaffold fully committed; the real thing appears above it —
        // Bodyweight Basics staged and startable.
        XCTAssertTrue(app.staticTexts["Schedule set"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["startStagedButton"].waitForExistence(timeout: 10))
        snap("setup-complete")
    }

    /// The welcome beat (opt-in via --uitest-welcome; every other test
    /// launches straight into the tabs): ONE screen now — the mark, the
    /// name, the idea, and a single "Get started" that drops into the
    /// app. The old mechanics + Health screens are gone (the Health ask
    /// moved to a contextual primer on the first workout).
    func testWelcomeFlow() throws {
        app.terminate()
        app.launchArguments += ["--uitest-welcome"]
        app.launch()

        let start = app.buttons["welcomeStartButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["PlusPlus"].exists, "the one screen is the idea")
        snap("welcome-idea")
        start.tap()

        // The intro yields to the app proper. The tab bar EXISTS under
        // the overlay the whole time, so existence proves nothing —
        // hittability is the dismissal signal.
        let today = tabButton("today")
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == 1"), object: today)
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 10), .completed, "the welcome screen must land in the tabbed app")
        snap("welcome-done")

        // Seen once means seen: a relaunch (no reset of the flag inside
        // one run) must not re-show the intro… but --uitest-welcome
        // forces it back on at every launch, so that assertion belongs
        // to the flag's default path, covered by every other test here
        // launching welcome-free.
    }

    // MARK: - Helpers

    /// Waits for an element's accessibility VALUE to become `value` — for
    /// stepper readouts that render inside buttons, where the label is the
    /// metric name and the number lives in the accessibility value. The
    /// timeout must absorb accessibility-snapshot latency: on a loaded CI
    /// simulator a single evaluation has been observed to take ~15 s.
    private func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 30) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Reveal a swipe row's DELETE action with the gentle, low-momentum
    /// drag the swipe-survives-release contract requires, and confirm it
    /// lands HITTABLE. XCUITest's synthesized slow-drag is under-shot or
    /// dropped on loaded CI runners (#273/#274) — leaving DELETE present but
    /// not (yet) hittable — so this waits for hittability and, failing that,
    /// re-drags, bounded to four attempts. It does not weaken the regression
    /// this test guards: a gentle release that SHUTS the row is deterministic,
    /// so it fails every attempt and this returns false; only the runner's
    /// gesture jitter is absorbed.
    @discardableResult
    private func revealDelete(_ start: XCUICoordinate, _ delete: XCUIElement) -> Bool {
        let hittable = NSPredicate(format: "hittable == 1")
        for _ in 0..<4 {
            start.press(
                forDuration: 0.05,
                thenDragTo: start.withOffset(CGVector(dx: -120, dy: 0)),
                withVelocity: .slow,
                thenHoldForDuration: 0.4
            )
            let expectation = XCTNSPredicateExpectation(predicate: hittable, object: delete)
            if XCTWaiter().wait(for: [expectation], timeout: 4) == .completed { return true }
        }
        return false
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Pop the pushed screen, whichever chrome it wears.
    ///
    /// The app has TWO back controls. Most pushed screens keep
    /// `pushedScreenChrome`'s custom key (`backButton`): catalog and template
    /// details, the record, routine settings. Routine detail does NOT — it
    /// moved to a system large title on 2026-07-29 (#470) for the native
    /// collapse, and the system supplies Back, so the custom key went with the
    /// chrome. A helper that knows only one of them walks off a cliff the
    /// moment a screen changes chrome, which is exactly what happened.
    private func tapBack(_ context: String, timeout: TimeInterval = 5) {
        let custom = app.buttons["backButton"]
        if custom.waitForExistence(timeout: timeout) {
            custom.tap()
            return
        }
        // The system bar's back button is the leading item; routine detail's
        // own keys are all trailing.
        let system = app.navigationBars.buttons.element(boundBy: 0)
        if system.exists {
            system.tap()
            return
        }
        XCTFail("no back control on \(context): \(buttonInventory())")
    }

    /// The buttons currently on screen, for a failure message.
    ///
    /// A remote session cannot reach the `ui-screenshots` artifact (it lives
    /// on blob storage the sandbox is blocked from), but the ui-test job
    /// publishes assertion text as `::error::` annotations, which the API
    /// does serve. So when a query misses, the message is the only channel
    /// that can say what was actually on screen — worth the characters.
    private func buttonInventory(_ limit: Int = 10) -> String {
        inventory(app.buttons, limit: limit)
    }

    private func textInventory(_ limit: Int = 10) -> String {
        inventory(app.staticTexts, limit: limit)
    }

    /// A frame as four integers, short enough to survive the annotation's
    /// 400-character cut.
    private func rect(_ frame: CGRect) -> String {
        "(\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height)))"
    }

    private func inventory(_ query: XCUIElementQuery, limit: Int) -> String {
        let names = query.allElementsBoundByIndex.prefix(limit).map { element -> String in
            let id = element.identifier
            return id.isEmpty ? element.label : id
        }
        return "on screen: " + names.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func createRoutine(named name: String) {
        // The routines catalog IS the search scope (2026-07-25), so its top
        // row creates inline rather than deep-linking anywhere: with no query
        // it asks for a name, and the routine LANDS back on the list with the
        // entrance flash, where the helper walks into its detail.
        goToCatalog("routines")

        let plus = app.buttons["newRoutineButton"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        plus.tap()

        let alert = app.alerts["New routine"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let field = alert.textFields.firstMatch
        field.tap()
        field.typeText(name)
        alert.buttons["Create"].tap()

        // Lands on the Routines list (one landing for every add); the new
        // card appears after its held-out entrance beat.
        let card = app.staticTexts[name]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()

        // The routine detail (custom header — no system navigation bar).
        XCTAssertTrue(app.buttons["addExerciseButton"].waitForExistence(timeout: 5))
    }

    private func search(for text: String) {
        // The picker is a sheet whose field sits at the BOTTOM (2026-07-25) —
        // always visible, so there's no magnifier to expand first.
        let searchField = app.textFields["exercisePickerSearchField"].firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText(text)
    }

    private func addExercise(searching name: String) {
        app.buttons["addExerciseButton"].tap()
        search(for: name)
        let row = app.cells.staticTexts[name]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
    }

    /// Skips the rest countdown, retrying once if the tap landed during a
    /// view transition (a tap synthesized mid-transition can be dropped).
    private func skipRest(afterSet setIndex: Int) {
        let skip = app.buttons["skipRestButton"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "Rest screen should appear after set \(setIndex)")
        if setIndex == 1 {
            // The rest length is adjustable in both directions (2026-07-27).
            XCTAssertTrue(app.buttons["extendRestButton"].exists, "Rest screen should offer +15s")
            XCTAssertTrue(app.buttons["reduceRestButton"].exists, "Rest screen should offer −15s")
            snap("rest-countdown")
        }
        skip.tap()

        let complete = app.buttons["completeSetButton"]
        if !complete.waitForExistence(timeout: 5) && skip.exists {
            skip.tap()
        }
        XCTAssertTrue(complete.waitForExistence(timeout: 10), "Set \(setIndex + 1) screen should appear after skipping rest")
    }
}
