import Foundation
import SwiftUI
import SwiftData
import PlusPlusKit

/// The app's roots: Today, Browse, and search (Dave, 2026-08-05 — prototype A
/// of the navigation exploration; the three catalog tabs collapsed into one).
///
/// Tabs name MODES — doing, browsing, finding — never scopes of one surface.
/// Browse and search both render the same `CatalogScopeView`; WHICH catalog is
/// the scope wheel's job (`ScopeWheel`, the principal-row control both carry),
/// stated exactly once. The two instances share one `scope` state, so search
/// always opens on the catalog you were just browsing, and vice versa.
enum AppTab: String, CaseIterable {
    case today, browse
    /// It wears `Tab(role: .search)`, so the system renders it as the separated
    /// circle and morphs the bar into the search field when it's selected. The
    /// field narrows whichever catalog the scope is already on — selecting it
    /// deliberately leaves `scope` alone.
    case search

    var label: String { rawValue }
}

extension FindScope {
    /// The tab that OWNS this scope's landings: Browse, for all three. The
    /// search instance shows the same catalogs but never consumes an arrival
    /// — a landing switches away from search by definition
    /// (`CatalogScopeView.ownsLandings`).
    var tab: AppTab { .browse }
}

/// v4 navigation root (2026-08-05, prototype A of the structure exploration):
/// **Today · Browse · Search**. v3's five-tab bar spent three slots naming
/// scopes of ONE surface and then named the same scopes again in search's
/// principal row; now the tabs name modes and the scope is stated once, on the
/// scope wheel both catalog instances carry. History: #109 (bottom tabs, FAB
/// gone), 2026-07-25 (catalog tabs and search scopes became one view),
/// 2026-07-26 (five tabs, system chrome), docs/DECISIONS.md for the rest.
///
/// The chrome is the SYSTEM'S (Dave, 2026-07-25): the hand-drawn
/// `AppBottomBar` is deleted, and the search-role morph is rented from the
/// native `TabView`. The catalogs spent one 2026-07 build as a scope dialled
/// on a bottom-accessory wheel while the bar carried only Today and Search —
/// this shape is that idea landing where it belongs: the wheel rides the
/// NAVIGATION bar (the accessory never rises with the keyboard), and
/// `CatalogScopeView` exists for it to dial.
///
/// **The scope control is `ScopeWheel`**, a `.principal` navigation-bar item
/// between the ++ key and the kit switcher on BOTH catalog instances. It is
/// NOT `tabViewBottomAccessory`, NOT native `.searchScopes`, NOT a
/// `.bottomBar` item, NOT a hand-rolled segmented control — the four retired
/// homes and the seven-build account live in navigation.md and
/// docs/DECISIONS.md (2026-07-26; the segmented control the wheel replaces
/// was retired 2026-08-05).
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
    /// The query, and which catalog the app is looking at. The query belongs
    /// to the system's search presentation on the search-role tab; `scope` is
    /// SHARED by the Browse and search instances — one state, written by
    /// either wheel — so opening search narrows the catalog you were just
    /// browsing, and leaving search lands Browse where you left off. (The old
    /// per-tab literal-scope plumbing died with the catalog tabs: with no
    /// fixed-scope tabs there is no outgoing-catalog frame to hide.)
    @State private var query = ""
    @State private var scope: FindScope = .routines
    // Scroll-position sync between a catalog tab and search is GONE (build 139
    // shipped it; it did nothing on device). `.scrollPosition(id:)` does not
    // take on a `List` the way it does on a `ScrollView` + `scrollTargetLayout`,
    // and the remaining route observes scroll GEOMETRY, which is the documented
    // way to break the search-role morph. Not worth that trade for a
    // convenience — revisit only if the control moves off the TabView subtree.
    /// The slide-to-reveal drawer behind the ++ key (replaces the pushed
    /// AppMenuScreen). Lives here, above the tabs' NavigationStacks, so it
    /// moves the whole TabView as one layer.
    @State private var reveal = RevealController()
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
    }

    /// A landing leaves search first: a create lands on the catalog that owns
    /// it (the one-landing law), and that landing has to be VISIBLE — left
    /// searching, the entrance flash would play behind a filtered list.
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

    /// Land on a tab — and, for a catalog landing, on the catalog that owns
    /// it: an arrival dials the shared scope so Browse (and search, next time
    /// it opens) is looking at the list the add landed on.
    private func land(on newTab: AppTab, scope newScope: FindScope? = nil) {
        query = ""
        if let newScope { scope = newScope }
        tab = newTab
    }

    /// The catalog, once, parameterized by which instance. Browse and search
    /// render THIS — there is one catalog screen in the app, and the shared
    /// `scope` decides what both are looking at. `isSearch` marks the one
    /// instance that carries the system field.
    private func catalog(on appTab: AppTab, isSearch: Bool = false) -> some View {
        CatalogScopeView(scope: scope, query: $query, tab: appTab, scopeSelection: $scope, isSearch: isSearch)
    }

    private var appContent: some View {
        // Today · Browse · Search (Dave, 2026-08-05). Browse and the search
        // tab render THE SAME view: the scope wheel decides which catalog,
        // never which screen, so moving between catalogs reads as one surface
        // changing scope — and moving between Browse and search reads as the
        // same room with the query on or off.
        TabView(selection: $tab) {
            Tab("Today", systemImage: todayStatus.systemImage, value: AppTab.today) {
                TodayView(onGoToRoutines: { land(on: .browse, scope: .routines) })
            }
            Tab("Browse", systemImage: "square.grid.2x2", value: AppTab.browse) {
                catalog(on: .browse)
            }
            // The SEARCH ROLE (Dave, 2026-07-26: "the sort of search tab that
            // makes the search input expand out of it to the side"). The role is
            // a package deal — the system floats it apart as the separated
            // circle AND gives it the morph into the field — and the morph is
            // the half worth having. A plain tab seats search in the group but
            // leaves the field homeless: `.searchable` then wants the navigation
            // bar this screen hides, which is why build 135 had no visible input
            // at all. Only THIS tab carries the field, for the same reason.
            Tab(value: AppTab.search, role: .search) {
                // ⚠️ The field is NOT attached here. It goes INSIDE
                // `CatalogScopeView`'s own `NavigationStack` — see its
                // `isSearch` note. Build 140 attached it out here and the
                // scope presentation never worked: `.searchable` needs a view
                // inside a navigation container, and out here the modifier
                // lands above that stack. The FIELD still morphed (the tab
                // role does that), which is what made it look wired up.
                catalog(on: .search, isSearch: true)
            }
        }
        // ⚠️ NOTHING rides `tabViewBottomAccessory` any more. The scope control
        // lived there for four builds and the container was always wrong: it
        // does not rise with the keyboard, so search's own keyboard buried it.
        // It is a `.principal` NAVIGATION BAR item on both catalog roots now —
        // see `ScopeWheel` and navigation.md, which carry the whole account.
        //
        // ⚠️ NO `.tabViewSearchActivation(.searchTabSelection)` here, and that
        // absence is deliberate. Build 143 added it to force a fresh scope-bar
        // presentation on every arrival; native scopes are gone, so that
        // justification went with them. Arriving without the keyboard also
        // means arriving with the whole surface in view — pick a catalog first,
        // tap the field when you actually want to type.
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
        // the reveal controller told which tab is showing.
        .onChange(of: tab, initial: true) { _, newTab in
            reveal.activeTab = newTab.rawValue
            // The scope needs no syncing here: Browse and search share the one
            // state, so each already opens on the catalog the other was
            // looking at. A tab switch changes the mode, never the catalog.
            //
            // The query belongs to search and dies with it. Only the search tab
            // has a field, so a query that outlived it would leave a filtered
            // list with nothing on screen explaining the filter and no way to
            // clear it — the "stale invisible query reads as data loss" law.
            if newTab != .search { query = "" }
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
        // A routine added from outside Browse (Today's setup step, a share
        // import, search) lands ON the routines catalog with the entrance
        // flash — one landing for every add (Dave, 2026-07-23). The landing
        // dials Browse's scope, so the list the flash plays on is the one on
        // screen.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusRoutineArrived)) { _ in
            land(on: .browse, scope: .routines)
        }
        // The exercise/equipment twins: a create/add lands on its catalog,
        // same one-landing law.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusExerciseArrived)) { _ in
            land(on: .browse, scope: .exercises)
        }
        .onReceive(NotificationCenter.default.publisher(for: .plusplusEquipmentArrived)) { _ in
            land(on: .browse, scope: .kit)
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
/// surface (Dave, build 44: "every root view, not just Today"). The glyph
/// stays brand green — content is the brand, the key says "press me". It no
/// longer pushes onto a tab's stack; it toggles the shared reveal drawer,
/// which slides the whole app aside to uncover the surface beneath.
struct AppMenuKey: View {
    @Environment(RevealController.self) private var reveal

    var body: some View {
        Button { reveal.toggle() } label: {
            HeaderGlyph()
                .frame(width: 44, height: 44)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.keyRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius).strokeBorder(Theme.borderStrong))
        }
        .buttonStyle(.raisedKey())
        .accessibilityLabel("Menu")
        .accessibilityHint(reveal.isOpen ? "Closes the menu" : "Opens the menu and settings")
        .accessibilityIdentifier("appMenuButton")
    }
}
