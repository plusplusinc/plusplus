import SwiftUI

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

    init() {
        // The launch beat: the ++ mark centered, then the app. Skipped
        // under UI tests (speed + quiescence). Everyone lands on Today —
        // a fresh install's timeline IS the onboarding (setup steps
        // render as gated entries there).
        _showingSplash = State(initialValue: !CommandLine.arguments.contains("--uitest-reset"))
    }

    var body: some View {
        // Native TabView (iOS 26 Liquid Glass) over the v3 custom bar:
        // system hit targets, accessibility, and scroll-edge treatment
        // for free — and per-tab navigation state survives switching.
        // The quiet-terminal identity lives in the content; the chrome
        // is the platform's (Dave, build 10 feedback).
        TabView(selection: $tab) {
            Tab("today", systemImage: "smallcircle.filled.circle", value: AppTab.today) {
                TodayView(onGoToRoutines: { tab = .routines })
            }
            Tab("routines", systemImage: "square.stack", value: AppTab.routines) {
                RoutineListView()
            }
            Tab("exercises", systemImage: "list.bullet", value: AppTab.exercises) {
                ExercisesTabView()
            }
            Tab("equipment", systemImage: "dumbbell", value: AppTab.equipment) {
                EquipmentTabView()
            }
        }
        .tint(Theme.textPrimary)
        .overlay {
            if showingSplash {
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
