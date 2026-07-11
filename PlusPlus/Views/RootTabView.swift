import Foundation
import SwiftUI
import PlusPlusKit

/// v3 navigation root (#109): four bottom tabs — Today · Routines ·
/// Exercises · Equipment. Creation is contextual (each tab's header +
/// creates its own thing); the FAB menu and the History destination are
/// gone (Today's timeline subsumes history, #110).
struct RootTabView: View {
    enum AppTab: String, CaseIterable {
        case today, routines, exercises, equipment

        var label: String { rawValue }
    }

    @State private var tab: AppTab = .today
    @State private var showingSplash: Bool
    /// The welcome beat (first launch only): three screens — the idea,
    /// the mechanics, the Health ask — then Today's setup timeline
    /// takes over as always.
    @State private var showingWelcome: Bool
    /// A share link the app was opened with, awaiting import (#145).
    @State private var shareImport: ShareImport?
    /// Post-install return from GitHub (the Setup-URL bounce, #23): present
    /// the connect step so the user just authorizes.
    @State private var showGitHubConnect = false

    init() {
        // The launch beat: the ++ mark centered, then the app. Skipped
        // under UI tests (speed + quiescence). Everyone lands on Today —
        // a fresh install's timeline IS the onboarding (setup steps
        // render as gated entries there). The welcome flow replaces the
        // splash the one time it shows — its first page IS the mark.
        let welcome = !SetupState.welcomeSeen
        _showingWelcome = State(initialValue: welcome)
        _showingSplash = State(initialValue: !welcome && !CommandLine.arguments.contains("--uitest-reset"))
    }

    var body: some View {
        // Native TabView (iOS 26 Liquid Glass) over the v3 custom bar:
        // system hit targets, accessibility, and scroll-edge treatment
        // for free — and per-tab navigation state survives switching.
        // The quiet-terminal identity lives in the content; the chrome
        // is the platform's (Dave, build 10 feedback).
        TabView(selection: $tab) {
            Tab("Today", systemImage: "smallcircle.filled.circle", value: AppTab.today) {
                TodayView(onGoToRoutines: { tab = .routines })
            }
            Tab("Routines", systemImage: "square.stack", value: AppTab.routines) {
                RoutineListView()
            }
            Tab("Exercises", systemImage: "list.bullet", value: AppTab.exercises) {
                ExercisesTabView()
            }
            Tab("Equipment", systemImage: "dumbbell", value: AppTab.equipment) {
                EquipmentTabView()
            }
        }
        .tint(Theme.textPrimary)
        .overlay {
            if showingWelcome {
                WelcomeView {
                    withAnimation(.easeOut(duration: 0.35)) {
                        showingWelcome = false
                    }
                }
                .transition(.opacity)
            } else if showingSplash {
                splash
            }
        }
        .task {
            guard showingSplash else { return }
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation(.easeOut(duration: 0.35)) {
                showingSplash = false
            }
        }
        // plusplus://r#… (and, once universal links land, the https
        // viewer URL) opens the import preview. A bad payload is
        // ignored — the viewer webpage is the place that explains.
        .onOpenURL { url in
            // Widget taps land on Today (#147).
            if url.scheme == RoutineShareLink.appScheme, url.host == "today" {
                tab = .today
                return
            }
            // Post-install bounce from GitHub (plusplus://github/connected):
            // present the connect step, which auto-starts the device flow.
            if url.scheme == RoutineShareLink.appScheme, url.host == "github" {
                showGitHubConnect = true
                return
            }
            guard RoutineShareLink.isShareLink(url),
                  let payload = try? RoutineShareLink.payload(from: url)
            else { return }
            shareImport = ShareImport(payload: payload)
        }
        // Universal-link form of the same GitHub Setup-URL return
        // (https://plusplus.fit/github/…), for when it opens the app directly.
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL, url.path.hasPrefix("/github") {
                showGitHubConnect = true
            }
        }
        // Siri/Shortcuts "Start Routine" (#147): the intent posts, the
        // root switches to Today, and Today starts the session.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusStartRoutine)) { _ in
            tab = .today
        }
        // Closing a finished workout's recap goes home: whatever screen
        // presented the session cover, the finish lands on Today, where
        // the just-committed card converts itself to done.
        .onReceive(NotificationCenter.default.publisher(for: .plusplusWorkoutFinished)) { _ in
            tab = .today
        }
        .sheet(item: $shareImport) { item in
            ShareImportSheet(payload: item.payload)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showGitHubConnect) {
            NavigationStack {
                GitHubConnectScreen(autoConnect: true)
            }
        }
    }

    private var splash: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Text("++")
                .font(.system(size: 72, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.accent)
        }
        .transition(.opacity)
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

/// The ++ wearing its key — every root header's top-left opens the
/// app page (Dave, build 44: "every root view, not just Today"). The
/// glyph stays brand green — content is the brand, the key says
/// "press me". Each tab presents its own AppMenuScreen so the push
/// rides that tab's stack.
struct AppMenuKey: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HeaderGlyph()
                .frame(width: 44, height: 44)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.borderStrong))
        }
        .buttonStyle(.raisedKey())
        .accessibilityIdentifier("appMenuButton")
    }
}
