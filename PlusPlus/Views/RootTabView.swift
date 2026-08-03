import Foundation
import SwiftUI
import SwiftData
import PlusPlusKit

/// The app's roots: Today and the three catalogs (Dave, 2026-08-02 — the
/// SEARCH tab is gone; search is the SYSTEM's, via `.searchable` +
/// `.searchToolbarBehavior(.minimize)` on each catalog stack).
///
/// The catalog cases are NOT three different screens — all three render the
/// same `CatalogScopeView`, and picking one only decides which catalog it
/// looks at. Switching between them is meant to read as one surface changing
/// scope, which is why nothing in that path re-mounts.
enum AppTab: String, CaseIterable {
    case today, routines, exercises, equipment

    var label: String { rawValue }
}

extension FindScope {
    /// The tab that selects this scope.
    var tab: AppTab {
        switch self {
        case .routines: return .routines
        case .exercises: return .exercises
        case .kit: return .equipment
        }
    }

}

/// v3 navigation root (#109): bottom tabs, creation contextual (each tab's
/// header + creates its own thing); the FAB menu and the History destination
/// are gone (Today's timeline subsumes history, #110).
///
/// 2026-07-25: **searching a catalog and browsing it are the same view.**
/// Search adds a query to `CatalogScopeView`, it does not take you to a
/// different screen. The older `RoutineListView` /
/// `ExercisesTabView` / `EquipmentTabView` / `FindOrCreateView` are gone, their
/// swipes, reorder and creates absorbed into that one surface (their facet
/// chips deliberately were NOT — the three read alike now, and the field
/// reaches what the chips used to).
///
/// The chrome is the SYSTEM'S (Dave, 2026-07-25), and the bar carries FOUR tabs
/// (Dave, 2026-08-02): Today · Routines · Exercises · Kit. The hand-drawn
/// `AppBottomBar` is deleted; its three device bugs (content scrolling through
/// it unreadably, no home-indicator clearance, labels off a common baseline)
/// were all things a real tab bar does for free.
///
/// The catalogs spent one build as a scope you dialled on a bottom-accessory
/// wheel while the bar carried only Today and Search. They are tabs again —
/// but now that `CatalogScopeView` exists they are tabs over ONE screen, which
/// is what the two-tab round was really after.
///
/// **The tab bar is the scope control, full stop** (Dave, 2026-08-02). The
/// SEARCH tab and its segmented scope `Picker` are both gone: search is a
/// floating key above the bar — the SYSTEM's, from `.searchable` +
/// `.searchToolbarBehavior(.minimize)` (see `CatalogScopeView.tabStack`), so
/// the tabs stay visible and usable while you search and there is
/// nothing left for a second scope control to do. The one accepted cost is that
/// the keyboard covers the tab bar, so changing catalog mid-query means
/// dismissing it first — which is what makes the catalogs'
/// `.scrollDismissesKeyboard` load-bearing rather than incidental.
struct RootTabView: View {

    /// The Today tab's icon reflects whether there's anything to do today
    /// (2026-07-24) — onboarding steps or scheduled workouts — so it lives
    /// at the root, computed from queries here (the icon must stay live
    /// even when Today isn't the front tab, so it can't wait on TodayView's
    /// body). Same finished-session filter and routine set TodayView reads.
    @Query(sort: \Routine.order) private var routines: [Routine]
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil })
    private var finishedSessions: [WorkoutSession]
    @AppStorage(SetupState.equipmentDoneKey) private var equipmentDone = false
    /// The schedule step's no-schedule completion (#505, Q26-A) — the
    /// tab icon must agree with the timeline's 3-of-3.
    @AppStorage(SetupState.trainingFreestyleKey) private var trainingFreestyle = false
    /// Bumped on day change so the Today icon re-derives at midnight (the
    /// same guard TodayView uses against a resident app rendering
    /// yesterday's plan).
    @State private var dayToken = 0

    @State private var tab: AppTab = .today
    /// The search query and whether the field is open — ONE source of truth for
    /// all three catalogs (Dave, 2026-08-02). They live at the root, not in
    /// `CatalogScopeView`, because a `Tab`'s content is its own view tree: three
    /// live instances would otherwise carry three unrelated queries.
    ///
    /// Both SURVIVE a tab switch, deliberately. Typing "bench" on Routines and
    /// tapping Exercises keeps the query, and a trip to Today (where the dock
    /// doesn't render) restores the open field on the way back rather than
    /// dropping what you typed. That does not violate the "a stale invisible
    /// query reads as data loss" law — it satisfies it: the query is only ever
    /// hidden on a tab that couldn't have been filtered by it, and it comes back
    /// visible, in an open field, with its own clear key.
    ///
    /// The three things that DO clear it: the in-field `delete.left`, the
    /// collapse key, and `land(on:)`.
    @State private var query = ""
    @State private var searchOpen = false
    // Scroll-position sync between catalog tabs is GONE (build 139 shipped it;
    // it did nothing on device). `.scrollPosition(id:)` does not take on a
    // `List` the way it does on a `ScrollView` + `scrollTargetLayout`, and the
    // remaining route observes scroll GEOMETRY. The morph that geometry reads
    // used to break died with the search tab, so the objection now is only that
    // it cost a probe and bought nothing.
    /// The slide-to-reveal drawer behind the ++ key (replaces the pushed
    /// AppMenuScreen). Lives here, above the tabs' NavigationStacks, so it
    /// moves the whole TabView as one layer.
    @State private var reveal = RevealController()
    /// What screen is frontmost, as one compact line — Operator's
    /// view-context (injected app-wide; screens report via
    /// `.operatorContext(_:)`).
    @State private var viewContext = ViewContext()
    /// The launch beat (splash + first-launch welcome, fused): a cold open
    /// always opens on the `++` mark; `introShowsWelcome` decides whether
    /// it settles into the welcome content or dissolves straight to Today.
    @State private var showingIntro: Bool
    private let introShowsWelcome: Bool
    private let introInstant: Bool
    /// A share link the app was opened with, awaiting import (#145).
    @State private var shareImport: ShareImport?
    /// A tapped share link whose payload couldn't be read — said out
    /// loud, never silently dropped (design review 2026-07-23).
    @State private var showShareLinkError = false
    /// The GitHub tray, and WHICH door opened it. ⚠️ ONE `@State` behind
    /// ONE `.sheet(item:)`, never two booleans behind two sheets (#509
    /// review): a view can only present one sheet, so a second request
    /// arriving while the first is up is silently dropped AND latches its
    /// flag true — after which every later request is a no-op assignment
    /// and the post-install auto-return is dead until relaunch.
    ///
    /// That is not a hypothetical ordering: the commonest repair for a
    /// broken sync is re-installing the Sync App, `openInstall()` leaves
    /// the app on purpose so the Setup URL can bounce back, and the bounce
    /// lands while the tray the user opened from Today is still on screen.
    /// As an item, a second request REPLACES the first instead of racing it.
    /// `RevealSurface`'s two-sheet pair has a pending-queue for the same
    /// reason; this one has a single slot, which is simpler and enough.
    enum GitHubSheet: String, Identifiable {
        /// Post-authorize return from github.com — opens on the connect step.
        case connect
        /// Today's broken-sync advisory, and any other plain entry: the tray
        /// where it seats itself. That is decided by whether this device
        /// holds a token, not by which door opened it (#509, Q18-A) — a
        /// broken sync has none, so it lands on step 1, which is the only
        /// thing that can help it.
        case tray
        var id: String { rawValue }
    }
    @State private var githubSheet: GitHubSheet?
    /// #155: the store couldn't be opened and was reset this launch. Read
    /// once at init (the flag is set during app init, before any view), so
    /// we tell the user rather than pretending nothing happened.
    @State private var showStoreResetNotice: Bool

    init() {
        // The launch beat: a cold open ALWAYS opens on the ++ mark
        // (IntroView), then the app. On first launch the same mark settles
        // into the welcome content; on later launches it just holds a beat
        // and dissolves to Today. Everyone lands on Today — a fresh
        // install's timeline IS the onboarding (setup steps render as gated
        // entries there).
        let welcome = !SetupState.welcomeSeen
        let uitest = CommandLine.arguments.contains("--uitest-reset")
        // Under UI test the pure-splash (returning-user) case is skipped so
        // the smoke suite lands on the tabs immediately; the welcome test
        // still gets its screen (it forces welcomeSeen false).
        _showingIntro = State(initialValue: welcome || !uitest)
        introShowsWelcome = welcome
        introInstant = uitest
        _showStoreResetNotice = State(initialValue: SetupState.storeWasReset)
    }

    /// The Today tab's icon: dashed-open when work waits, filled-checkmark
    /// when today's work is done, plain-open when the day held nothing.
    private var todayStatus: TodayStatus {
        _ = dayToken
        return TodayStatus.current(
            routines: routines,
            sessions: finishedSessions,
            equipmentDone: equipmentDone,
            trainingFreestyle: trainingFreestyle,
            today: Date(),
            calendar: .current
        )
    }

    var body: some View {
        // The whole app rides inside the reveal drawer: tapping ++ slides
        // this TabView aside to uncover the app surface beneath it.
        RevealContainer(controller: reveal) {
            routedAppContent
        }
        // Injected here so BOTH layers see it: the tabs report context,
        // the reveal surface (Operator) reads it.
        .environment(viewContext)
    }

    @MainActor
    /// A share link from anywhere — a tapped URL or a pasted one (#509,
    /// b17). One handler, so both entry points fail the same way.
    private func openShareLink(_ url: URL) {
        guard RoutineShareLink.isShareLink(url) else { return }
        if let payload = try? RoutineShareLink.payload(from: url) {
            shareImport = ShareImport(payload: payload)
        } else {
            // A raw plusplus://r#… link pasted in Messages/Notes has no
            // viewer webpage to explain a bad payload — say it here instead
            // of swallowing the tap (design review 2026-07-23).
            showShareLinkError = true
        }
    }

    /// ⚠️ A landing CLOSES search as well as clearing it. The one-landing law
    /// says every add lands on its list with the entrance flash, and that
    /// landing has to be VISIBLE — left searching, the flash would play on a
    /// row inside a filtered list, or on no row at all.
    private func land(on newTab: AppTab) {
        // Animated, because the landing may not change tab at all: creating an
        // exercise from the create row ON the Exercises tab fires
        // `.plusplusExerciseArrived`, so an unanimated assignment snaps the
        // field shut in the frame before the entrance flash plays.
        withAnimation(Theme.Anim.selection) {
            query = ""
            searchOpen = false
        }
        tab = newTab
    }

    /// The catalog, once, parameterized by which one. Every catalog tab renders
    /// THIS — there is one catalog screen in the app, and a tab only decides
    /// what it is looking at.
    ///
    /// Each tab passes its own scope as a LITERAL. It has to: a `Tab`'s content
    /// is its own view tree, so a shared `scope` would render one frame with the
    /// OUTGOING catalog before any `onChange` caught up — a flash of the
    /// previous list on every switch.
    private func catalog(_ shown: FindScope, on appTab: AppTab) -> some View {
        CatalogScopeView(
            scope: shown,
            query: $query,
            searchOpen: $searchOpen,
            tab: appTab,
            // ⚠️ Only the SELECTED tab may PRESENT search. All three catalogs
            // are mounted at once and share one `searchOpen`; without this the
            // flag presented all three `.searchable`s together — see
            // `CatalogScopeView.presentedBinding` for the full account.
            isActive: tab == appTab
        )
    }

    private var appContent: some View {
        // Today · Routines · Exercises · Kit (Dave, 2026-08-02). The three
        // catalog tabs all render THE SAME view: a tab decides which catalog,
        // never which screen, so moving between them reads as one surface
        // changing scope rather than three screens.
        TabView(selection: $tab) {
            // Operator's context: the tab line comes from the onChange below;
            // pushed details report (and clear) their own via .operatorContext.
            Tab("Today", systemImage: todayStatus.systemImage, value: AppTab.today) {
                TodayView(onGoToRoutines: { land(on: .routines) })
            }
            // ⚠️ These do NOT hide while search is active, and now they must
            // not: the whole point of the floating key is that the tabs stay
            // usable during a search, so they ARE the scope control. (They
            // never should have: `Tab.hidden(_:)` works but the bar does not
            // REFLOW around hidden tabs — build 139 left a full-width group
            // capsule with Today rattling around alone in it.)
            Tab(FindScope.routines.label, systemImage: FindScope.routines.symbolName, value: AppTab.routines) {
                catalog(.routines, on: .routines)
            }
            Tab(FindScope.exercises.label, systemImage: FindScope.exercises.symbolName, value: AppTab.exercises) {
                catalog(.exercises, on: .exercises)
            }
            // Labeled "Kit" (2026-07-20); the enum case stays `.equipment`.
            Tab(FindScope.kit.label, systemImage: FindScope.kit.symbolName, value: AppTab.equipment) {
                catalog(.kit, on: .equipment)
            }
        }
        // ⚠️ NOTHING rides `tabViewBottomAccessory`, and the floating search
        // dock must not either. The scope control lived there for four builds
        // and the container was always wrong: it does not rise with the
        // keyboard, so search's own keyboard buried it — and it refuses
        // app-authored animation (138), so the dock's morph would die there
        // too. The dock is a bottom `safeAreaInset` INSIDE each catalog tab's
        // navigation stack; the system owns it now.
        //
        // ⚠️ There is no `Tab(role: .search)` any more (Dave, 2026-08-02), so
        // `.tabViewSearchActivation` has nothing to activate and the iOS 26
        // morph bug (nav-diag 4e — a state-writing geometry read in this
        // subtree breaking the search-role morph on first activation) has lost
        // its consumer along with it.
        //
        // ⚠️ NO `.tabBarMinimizeBehavior(.onScrollDown)` either (Dave,
        // 2026-07-27). It only ever existed to move the bottom accessory
        // between its `.expanded` and `.inline` placements, which is what
        // decided whether the old scope control showed icon + label or icon
        // only. The accessory died on 149 and nothing reads
        // `tabViewBottomAccessoryPlacement` now, so all the modifier still did
        // was shrink the bar out from under your thumb on the way down a
        // catalog. The bar stays at full size; the `.soft` bottom scroll edge
        // effect on each scrolling root is what keeps rows from reading
        // through it.
        .tint(Theme.textPrimary)
        // Swipe-to-open is gated on the active tab being at its root; keep
        // the reveal controller told which tab is showing. Operator's
        // view-context follows the same signal (a tab switch also clears
        // a popped detail's stale line).
        .onChange(of: tab, initial: true) { _, newTab in
            reveal.activeTab = newTab.rawValue
            viewContext.tab = newTab.rawValue
            viewContext.detail = nil
            // ⚠️ The query is NOT cleared here (Dave, 2026-08-02, reversing
            // the search-tab behaviour). It is one query across all three
            // catalogs and it survives Today; see `query`'s own note for why
            // that keeps the data-loss law rather than breaking it.
        }
        // Operator's outcome navigation: the root switches tabs; the
        // owning tab root resolves and pushes (the .plusplusStartRoutine
        // pattern). The drawer closes too, so a half-height Operator
        // tray shows the result landing behind it live (Dave, build-85
        // round) — and dismissing the tray lands on the result, not the
        // drawer.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusOperatorShow)) { note in
            guard let destination = note.object as? OperatorDestination else { return }
            switch destination {
            case .today: land(on: .today)
            case .routine: land(on: .routines)
            case .exercisesTab: land(on: .exercises)
            case .equipmentTab: land(on: .equipment)
            }
            reveal.close()
        }
        .overlay {
            if showingIntro {
                IntroView(showWelcome: introShowsWelcome, instant: introInstant) {
                    withAnimation(.easeOut(duration: 0.35)) {
                        showingIntro = false
                    }
                }
                .transition(.opacity)
            }
        }
    }

    /// ⚠️ The URL/notification routing and every app-level presentation live
    /// in their OWN `some View`, split off `appContent` (CI, 2026-08-02).
    /// That chain is ~230 lines of modifiers on one expression and it went
    /// over the type-checker's budget outright — "unable to type-check this
    /// expression in reasonable time" — the moment the GitHub sheet became
    /// an `item:` presentation with a ternary in its builder. Same budget
    /// `TodayView.committedHistory` was extracted for. A `some View`
    /// boundary is what keeps it checkable, so anything added here from now
    /// on belongs BELOW this line, not above it.
    private var routedAppContent: some View {
        appContent
        // plusplus://r#… (and, once universal links land, the https
        // viewer URL) opens the import preview. A bad payload is
        // ignored — the viewer webpage is the place that explains.
        .onOpenURL { url in
            // Widget taps land on Today (#147).
            if url.scheme == RoutineShareLink.appScheme, url.host == "today" {
                land(on: .today)
                return
            }
            // Post-install bounce from GitHub (plusplus://github/connected):
            // present the connect step, which auto-starts the device flow.
            if url.scheme == RoutineShareLink.appScheme, url.host == "github" {
                githubSheet = .connect
                return
            }
            // A calendar event's start link (plusplus://start/<name>, #333):
            // hand off to the same pathway Siri's StartRoutineIntent uses —
            // TodayView resolves the name and starts the session, the root
            // switches to Today.
            if let name = WorkoutCalendarLink.routineName(from: url) {
                NotificationCenter.default.post(name: .plusplusStartRoutine, object: name)
                return
            }
            openShareLink(url)
        }
        // The Data tray's paste (#509, b17) lands in the SAME handler a tap
        // does — so an unreadable payload gets the one explanation that
        // already exists rather than a second, quieter failure path.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusPastedShareLink)) { note in
            (note.object as? URL).map(openShareLink)
        }
        // Today's broken-sync advisory (#509, Q19-A). ⚠️ It presents the
        // tray DIRECTLY rather than opening the drawer and asking
        // `RevealSurface` to raise it (review). The drawer route needed a
        // second receiver over there, a sleep long enough to clear the
        // drawer's spring (a magic number Reduce Motion falsifies, since a
        // reduced open finishes early), and a cross-layer write into that
        // view's own presentation state — which its tray queue would fight
        // if anything else were already up. One receiver, one sheet, and
        // the user lands where the card promised instead of watching the
        // app slide aside first.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusOpenSyncTray)) { _ in
            githubSheet = .tray
        }
        // Universal-link form of the same GitHub Setup-URL return
        // (https://plusplus.fit/github/…), for when it opens the app directly.
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            if url.path == "/github/connected" || url.path.hasPrefix("/github/") {
                githubSheet = .connect
            } else if let name = WorkoutCalendarLink.routineName(from: url) {
                // https://plusplus.fit/start/<name> — the universal-link
                // form of a calendar event's start link (#333).
                NotificationCenter.default.post(name: .plusplusStartRoutine, object: name)
            }
        }
        // Siri/Shortcuts "Start Routine" (#147): the intent posts, the
        // root switches to Today, and Today starts the session.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusStartRoutine)) { _ in
            land(on: .today)
        }
        // Re-derive the Today icon at midnight — a resident app would
        // otherwise keep yesterday's due list (the same day-rollover guard
        // TodayView carries).
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            dayToken += 1
        }
        // A routine added from outside the Routines tab (Today's setup
        // step, a share import) lands ON the Routines list with the
        // entrance flash — one landing for every add (Dave, 2026-07-23).
        .onReceive(NotificationCenter.default.publisher(for: .plusplusRoutineArrived)) { _ in
            land(on: .routines)
        }
        // The exercise/equipment twins (universal search): a create/add
        // lands on its list, same one-landing law.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusExerciseArrived)) { _ in
            land(on: .exercises)
        }
        .onReceive(NotificationCenter.default.publisher(for: .plusplusEquipmentArrived)) { _ in
            land(on: .equipment)
        }
        // Closing a finished workout's recap goes home: whatever screen
        // presented the session cover, the finish lands on Today, where
        // the just-committed card converts itself to done.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusWorkoutFinished)) { _ in
            land(on: .today)
        }
        .sheet(item: $shareImport) { item in
            ShareImportSheet(payload: item.payload)
                .presentationDetents([.large])
        }
        .alert("That link couldn't be read", isPresented: $showShareLinkError) {
            Button("OK") {}
        } message: {
            Text("It may be incomplete or from a newer version of PlusPlus.")
        }
        .sheet(item: $githubSheet) { which in
            GitHubSyncTray(startAtConnect: which == .connect)
                // The same ground the drawer's trays wear. This route is
                // an everyday one from the home surface now, so a system
                // sheet background here would be the one place the warm
                // charcoal drops out (#509 review).
                .presentationCornerRadius(Theme.sheetRadius + 2)
                .presentationBackground(Theme.background)
        }
        // #155: never a silent wipe. If the store couldn't be opened and
        // was reset this launch, say so plainly (calm, no blame) and note
        // the saved backup. One-shot: the flag clears on dismiss.
        .alert("Your data was reset", isPresented: $showStoreResetNotice) {
            Button("OK") { SetupState.clearStoreResetFlag() }
        } message: {
            Text(SetupState.storeResetBackupSaved
                 ? "PlusPlus couldn't open your saved data, so it started fresh. A copy of the old data was saved to the Files app in case it can be recovered."
                 : "PlusPlus couldn't open your saved data, so it started fresh.")
        }
    }

}

/// The ++ glyph anchoring every tab header, top-left — the one place
/// the brand green appears in chrome.
struct HeaderGlyph: View {
    var body: some View {
        Text("++")
            .font(.system(.subheadline, design: .monospaced, weight: .bold))
            .foregroundStyle(Theme.accent)
    }
}

/// The ++ wearing its key — every root header's top-left opens the app
/// surface (Dave, build 44: "every root view, not just Today"). It no longer
/// pushes onto a tab's stack; it toggles the shared reveal drawer, which
/// slides the whole app aside to uncover the surface beneath.
///
/// ⚠️ NATIVE as of 2026-08-02 (Dave: make the toolbar buttons native rather
/// than the app's 3D key). It lives ONLY in the system navigation bar — both
/// call sites are `ToolbarItem`s — so unlike `HeaderIconButton` and
/// `LibrarySwitcherKey` it needs no raised variant at all. The toolbar plates
/// it, sizes it and gives it the press feedback; the app supplies the glyph.
///
/// The glyph stays brand GREEN. That is not chrome, it is the mark — the one
/// place the accent appears in the bar, and the reason it reads as a door
/// rather than a system affordance.
struct AppMenuKey: View {
    @Environment(RevealController.self) private var reveal

    var body: some View {
        Button { reveal.toggle() } label: {
            HeaderGlyph()
        }
        .accessibilityLabel("Menu")
        .accessibilityHint(reveal.isOpen ? "Closes the menu" : "Opens the menu and settings")
        .accessibilityIdentifier("appMenuButton")
    }
}
