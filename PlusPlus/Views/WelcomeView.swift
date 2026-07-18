import SwiftUI

/// The launch beat, splash and welcome fused into one continuous shot
/// (Dave, 2026-07-15). A cold open ALWAYS opens on the mark: the `++`
/// centered on the background. From there one of two things happens —
///
///  - first launch: the SAME glyph glides up and shrinks into its slot
///    above the name, and the idea + a single "Start building" key fade
///    in beneath it (the old separate splash→welcome hand-off, where the
///    mark popped from one size/place to another, is gone — it's one
///    element moved and scaled via `matchedGeometryEffect`).
///  - every later launch: the mark holds a beat, then the whole intro
///    dissolves into the tabs.
///
/// Tapping "Start building" plays the ignition: the key wipes green
/// left-to-right (the app's commit-landed grammar), its label morphs to
/// "let's go", and the lone chevron blooms into a three-chevron forward
/// march (two more slide out to the right, then a lit highlight travels
/// across them). Then a `.success` fires and the intro zooms through into
/// Today. Shown once per install; `instant` collapses every dwell/flourish
/// for the smoke suite.
struct IntroView: View {
    /// First launch lands on the welcome content; a returning user just
    /// gets the mark, then the tabs.
    let showWelcome: Bool
    /// Under UI test: no timed dwells, no ignition flourish — tap enters
    /// immediately so the smoke suite doesn't wait on real seconds.
    let instant: Bool
    let onFinished: () -> Void

    @Namespace private var glyph
    /// Reduce Motion quiets the ignition flourish (the chevron march is
    /// opacity, gentle, but the emerge slide is positional) — WCAG 2.3.3.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// false = the mark rests centered (splash); true = it has settled
    /// into its welcome slot above the name.
    @State private var atWelcome = false
    /// The name, tagline, and button fade in as the mark settles.
    @State private var contentVisible = false
    /// The tap is fired: green wipe + label morph + the chevron march.
    @State private var launching = false
    /// Which of the three chevrons is lit as the highlight travels
    /// left→right (forward motion) once the key ignites.
    @State private var chevronActive = 0
    /// The final dive — the intro scales up and dissolves into Today.
    @State private var divingIn = false
    @State private var launchTask: Task<Void, Never>?

    /// 72 pt centered on the splash; 64 pt in the welcome slot. One glyph,
    /// scaled — the font stays fixed (it can't animate) and `scaleEffect`
    /// carries the size change so the move interpolates smoothly.
    private let splashSize: CGFloat = 72
    private var welcomeScale: CGFloat { 64.0 / splashSize }

    /// Concentric-ish framing (Dave, 2026-07-15): equal side/bottom insets
    /// so the key's corners echo the display's, sitting up near where the
    /// screen starts to curve rather than pinned to the very bottom.
    private let edgeInset: CGFloat = 22
    private let keyRadius: CGFloat = 24

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            welcomeLayout

            // The splash slot: dead center of the screen.
            Color.clear
                .frame(width: 2, height: 2)
                .matchedGeometryEffect(id: "glyphSlot", in: glyph,
                                       properties: .position, isSource: !atWelcome)

            // The one true mark, following whichever slot is active.
            Text("++")
                .font(.system(size: splashSize, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .scaleEffect(atWelcome ? welcomeScale : 1)
                .matchedGeometryEffect(id: "glyphSlot", in: glyph,
                                       properties: .position, isSource: false)
                .accessibilityHidden(true)
        }
        .scaleEffect(divingIn ? 1.12 : 1)
        .opacity(divingIn ? 0 : 1)
        .task { await run() }
        .onDisappear { launchTask?.cancel() }
    }

    private var welcomeLayout: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                // Invisible twin: reserves the welcome slot so the real
                // mark has somewhere to fly to. Never drawn or spoken.
                Text("++")
                    .font(.system(size: splashSize, weight: .bold, design: .monospaced))
                    .scaleEffect(welcomeScale)
                    .opacity(0)
                    .matchedGeometryEffect(id: "glyphSlot", in: glyph,
                                           properties: .position, isSource: atWelcome)
                    .accessibilityHidden(true)
                Text("PlusPlus")
                    .font(.system(.title2, weight: .bold))
                Text("A hackable workout tracker for incrementing yourself")
                    .font(.system(.subheadline))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 36)
            .opacity(contentVisible ? 1 : 0)
            Spacer()
            startButton
                .opacity(contentVisible ? 1 : 0)
        }
        // `opacity(0)` does NOT remove a view from hit testing (this repo's
        // ui-interaction law): without this an invisible "Start building"
        // sits tappable through the whole splash dwell, so a stray tap would
        // fire the ignition (two haptics, wrong-path entry) before the
        // button is even visible — worst on the returning-user path, where
        // the content never fades in at all.
        .allowsHitTesting(contentVisible)
    }

    private var startButton: some View {
        Button {
            beginLaunch()
        } label: {
            HStack(spacing: 8) {
                // Reserve the width of the LONGER label so swapping
                // "Start building" for "let's go" can't change the text
                // box's width and shove the chevron (Dave): a hidden
                // placeholder fixes the box to "Start building", and the
                // live label rides inside it trailing-aligned, staying
                // snug against the chevron while its left edge does the
                // moving.
                Text("Start building")
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .hidden()
                    .overlay(alignment: .trailing) {
                        Text(launching ? "let's go" : "Start building")
                            .contentTransition(.opacity)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                chevronRun
            }
            .font(.system(.body, weight: .bold))
            .foregroundStyle(Theme.onPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .background {
                // The commit wipe: green fills left-to-right over the cap.
                ZStack(alignment: .leading) {
                    Theme.primaryFill
                    Theme.accent
                        .scaleEffect(x: launching ? 1 : 0, anchor: .leading)
                }
                .clipShape(RoundedRectangle(cornerRadius: keyRadius))
            }
        }
        .buttonStyle(.raisedPrimaryKey(cornerRadius: keyRadius))
        .disabled(launching)
        .accessibilityIdentifier("welcomeStartButton")
        .padding(.horizontal, edgeInset)
        .padding(.bottom, edgeInset)
    }

    /// At rest the key carries one chevron. When it ignites, two more
    /// slide out to its right and a lit highlight marches left→right
    /// across the trio (the others dimmed, not gone), so the tap reads
    /// as forward momentum before the dive to Today. Reduce Motion keeps
    /// the single static chevron.
    private var chevronRun: some View {
        HStack(spacing: 3) {
            Image(systemName: "chevron.right")
                .opacity(chevronOpacity(0))
            if launching && !reduceMotion {
                ForEach(1..<3, id: \.self) { index in
                    Image(systemName: "chevron.right")
                        .opacity(chevronOpacity(index))
                        // Emerge from behind the resting chevron (leading
                        // edge) so they read as coming out of it rightward.
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
        }
    }

    /// The lit chevron is full; its neighbours rest dim so the two that
    /// emerged stay visible as a track the highlight travels. Off-launch
    /// (or Reduce Motion) only the first chevron shows.
    private func chevronOpacity(_ index: Int) -> Double {
        guard launching && !reduceMotion else { return index == 0 ? 1 : 0 }
        return chevronActive == index ? 1 : 0.25
    }

    /// Splash dwell, then either settle into the welcome content or, for a
    /// returning user, hand straight off to the tabs.
    private func run() async {
        if !instant { try? await Task.sleep(for: .seconds(0.9)) }
        guard showWelcome else {
            onFinished()
            return
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            atWelcome = true
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.12)) {
            contentVisible = true
        }
    }

    /// The ignition (see the type doc): wipe → morph → chevron march → dive.
    private func beginLaunch() {
        guard !launching else { return }
        SetupState.markWelcomeSeen()
        guard !instant else {
            onFinished()
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeInOut(duration: 0.32)) {
            launching = true
        }
        launchTask = Task { @MainActor in
            if !reduceMotion {
                // Let the green wipe land and the two extra chevrons
                // emerge before the highlight starts travelling.
                try? await Task.sleep(for: .seconds(0.32))
                guard !Task.isCancelled else { return }
                // The forward march: the lit chevron sweeps left→right
                // across the trio twice (ending on the rightmost, aimed
                // at Today) — a beat's worth of momentum before the dive.
                for hop in 0..<6 {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        chevronActive = hop % 3
                    }
                    try? await Task.sleep(for: .seconds(0.15))
                    guard !Task.isCancelled else { return }
                }
            } else {
                // No march under Reduce Motion — just hold a beat so the
                // green wipe registers before the dive.
                try? await Task.sleep(for: .seconds(0.5))
                guard !Task.isCancelled else { return }
            }
            // The commit "thud", landing as the dive kicks off.
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.easeIn(duration: 0.3)) {
                divingIn = true
            }
            try? await Task.sleep(for: .seconds(0.28))
            guard !Task.isCancelled else { return }
            onFinished()
        }
    }
}
