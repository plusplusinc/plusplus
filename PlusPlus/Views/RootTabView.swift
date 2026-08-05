import Foundation
import SwiftUI
import SwiftData
import PlusPlusKit

/// The app's roots: Today, the three catalogs, and search (Dave, 2026-07-26).
///
/// The catalog cases are NOT four different screens — all four render the same
/// `CatalogScopeView`, and picking one only sets `scope`. Switching between them
/// is meant to read as one surface changing scope, which is why nothing in that
/// path re-mounts.
enum AppTab: String, CaseIterable {
    case today, routines, exercises, equipment
    /// An ORDINARY tab since 2026-08-05 (Dave: put the input at the top).
    /// It wore `Tab(role: .search)` from 2026-07-26, which rendered it as the
    /// separated circle and morphed the tab bar into the field at the BOTTOM —
    /// and that morph IS the bottom placement, so a top field and the role are
    /// two names for opposite things. The field narrows whichever catalog the
    /// scope is already on; selecting it deliberately leaves `scope` alone.
    case search

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

    /// The scope a tab selects — `nil` for the two that don't pick one: Today
    /// (a timeline of derived state, not a list of typed items) and search
    /// (which keeps whatever scope you were already on).
    init?(tab: AppTab) {
        switch tab {
        case .routines: self = .routines
        case .exercises: self = .exercises
        case .equipment: self = .kit
        case .today, .search: return nil
        }
    }
}

/// v3 navigation root (#109): bottom tabs, creation contextual (each tab's
/// header + creates its own thing); the FAB menu and the History destination
/// are gone (Today's timeline subsumes history, #110).
///
/// 2026-07-25: **the catalog tabs and the search scopes are the same three
/// views.** Tapping Routines with search closed and scoping to Routines with it
/// open land on one `CatalogScopeView` — search adds a query, it does not take
/// you to a different screen. The older `RoutineListView` /
/// `ExercisesTabView` / `EquipmentTabView` / `FindOrCreateView` are gone, their
/// swipes, reorder and creates absorbed into that one surface (their facet
/// chips deliberately were NOT — the three read alike now, and the field
/// reaches what the chips used to).
///
/// The chrome is the SYSTEM'S (Dave, 2026-07-25), and the bar carries FIVE tabs
/// (Dave, 2026-07-26): Today · Routines · Exercises · Kit · Search. The
/// hand-drawn `AppBottomBar` is deleted; its three device bugs (content
/// scrolling through it unreadably, no home-indicator clearance, labels off a
/// common baseline) were all things a real tab bar does for free.
///
/// The catalogs spent one build as a scope you dialled on a bottom-accessory
/// wheel while the bar carried only Today and Search. They are tabs again —
/// but now that `CatalogScopeView` exists they are tabs over ONE screen, which
/// is what the two-tab round was really after.
///
/// **The tab bar is the scope control; inside search, the system's own scope
/// bar is** — native `.searchScopes`, attached to the same `.searchable` that
/// carries the field, inside `CatalogScopeView`'s stack (2026-08-05, Dave:
/// another shot at it, reversing the app-drawn control that held the
/// `.principal` slot from 2026-07-26). It has never lived in
/// `tabViewBottomAccessory` successfully (that container does not rise with the
/// keyboard) and never in a `.bottomBar` item (that row is the one the
/// search-role field expands into); those two stay retired. What made the
/// system's answer worth re-trying, and what to check on device, is on
/// `SearchPresentation` in `CatalogScopeView`.
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
    /// The query, and which catalog SEARCH is looking at. Both live here
    /// because both belong to the system's search presentation on the
    /// search-role tab, not to the surface they drive.
    ///
    /// `scope` only ever decides what the SEARCH tab shows — the three catalog
    /// tabs carry their own — and it follows whichever of them you last picked,
    /// so opening search narrows where you already were.
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

    private func land(on newTab: AppTab) {
        query = ""
        tab = newTab
    }

    /// The catalog, once, parameterized by which one. Every catalog tab and the
    /// search tab render THIS — there is one catalog screen in the app, and a
    /// tab only decides what it is looking at.
    ///
    /// The three catalog tabs pass their own scope as a literal rather than
    /// reading `scope`: a `Tab`'s content is its own view tree, so it would
    /// otherwise render one frame with the OUTGOING scope before
    /// `onChange(of: tab)` caught up — a flash of the previous catalog every
    /// switch. Search is the one that reads the state, which is the whole point
    /// of the state: it keeps the catalog you were already on.
    private func catalog(
        _ shown: FindScope,
        on appTab: AppTab,
        searchScope: Binding<FindScope>? = nil
    ) -> some View {
        CatalogScopeView(scope: shown, query: $query, tab: appTab, searchScope: searchScope)
    }

    private var appContent: some View {
        // Today · Routines · Exercises · Kit · Search (Dave, 2026-07-26). The
        // three catalog tabs and the search tab all render THE SAME view: a tab
        // decides which catalog, never which screen, so moving between them
        // reads as one surface changing scope rather than four screens.
        TabView(selection: $tab) {
            // Operator's context: the tab line comes from the onChange below;
            // pushed details report (and clear) their own via .operatorContext.
            Tab("Today", systemImage: todayStatus.systemImage, value: AppTab.today) {
                TodayView(onGoToRoutines: { land(on: .routines) })
            }
            // ⚠️ These do NOT hide while search is active, though `Tab.hidden(_:)`
            // makes it easy to (build 139 did). The bar does not REFLOW around
            // hidden tabs: what's left is a full-width group capsule with Today
            // rattling around alone in the middle of it (Dave's screenshot).
            // Build 139 hid them to deliver Today beside the MORPHED field;
            // that motive died with the role (2026-08-05) — the bar now stays
            // whole while search is up — but the reflow finding is why nobody
            // should reach for `Tab.hidden` here again.
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
            // An ORDINARY tab (Dave, 2026-08-05: put the input at the top),
            // retiring `Tab(role: .search)` — which carried this surface from
            // 2026-07-26 and gave it two things at once: the separated circle
            // in the bar, and the morph of the bar INTO the field at the
            // bottom. ⚠️ **That morph IS the bottom placement.** Asking the
            // role for a top field is asking it to be both things, and the one
            // recorded sighting of a top field on this surface is the morph
            // FAILING (nav-diag 4e), which leaves the circle in the bar AND a
            // field up top — two search affordances. So the role goes, and
            // `.searchable` takes an explicit `.navigationBarDrawer` placement
            // instead (see `SearchPresentation`).
            //
            // ⚠️ Build 135's homeless field is NOT the hazard being re-run
            // here: that was a tab root that HID its navigation bar, so the
            // drawer had nowhere to attach. Since 2026-07-26 every root wears
            // the system bar, which is exactly the container a drawer needs.
            // ⚠️ The app owns this word now. The search ROLE supplied a
            // system-localized label and glyph; a plain tab supplies neither,
            // so "Search" and the magnifier are the app's to state — and to
            // localize, when localization arrives.
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) {
                // ⚠️ The field and the scope bar are NOT attached here. They go
                // INSIDE `CatalogScopeView`'s own `NavigationStack` — see its
                // `searchScope` note. Build 140 attached them out here and the
                // scope bar never appeared: `.searchScopes` needs `.searchable`
                // on a view inside a navigation container, and out here the
                // modifier lands above that stack. That was masked at the time
                // because the FIELD still appeared — the tab role morphed it —
                // which is what made it look wired up. With the role gone,
                // attaching out here would now fail visibly instead.
                catalog(scope, on: .search, searchScope: $scope)
            }
        }
        // ⚠️ NOTHING rides `tabViewBottomAccessory` any more. The scope control
        // lived there for four builds and the container was always wrong: it
        // does not rise with the keyboard, so search's own keyboard buried it.
        // Scoping is the system's `.searchScopes` bar now — see
        // `SearchPresentation` in `CatalogScopeView`.
        //
        // ⚠️ NO `.tabViewSearchActivation(.searchTabSelection)` here, and it is
        // no longer even available: that modifier addresses a SEARCH-ROLE tab,
        // and this tab is an ordinary one as of 2026-08-05. Build 143 used it
        // to force a fresh scope-bar presentation on every arrival. If the
        // scope bar turns out not to appear until the field is tapped, the
        // lever now is `.searchFocused` on arrival — which costs the same thing
        // 143's did (the keyboard up before you have looked at the surface),
        // and which Dave chose against on 2026-07-26. A drawer field is VISIBLE
        // unfocused, though, which the morphed one was not, so the trade is
        // milder than it was.
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
            // Picking a catalog tab IS picking a scope, so search opens on the
            // catalog you were just looking at. Search itself sets nothing —
            // that's what makes it a narrowing of where you already are.
            if let picked = FindScope(tab: newTab) { scope = picked }
            // The query belongs to search and dies with it. Only the search tab
            // has a field, so a query that outlived it would leave a filtered
            // list with nothing on screen explaining the filter and no way to
            // clear it — the "stale invisible query reads as data loss" law.
            if newTab != .search { query = "" }
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
