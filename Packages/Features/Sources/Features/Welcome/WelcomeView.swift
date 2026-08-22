import DesignSystem
import SwiftUI

#if os(iOS)
    import UIKit
#endif

/// The launch beat: splash and welcome fused into one continuous shot.
///
/// A cold open always opens on the mark — the `++` centered on the background. From there the same
/// glyph glides up and shrinks into its slot above the name, and the tagline and a single
/// "Start building" key fade in beneath it. It is one element moved and scaled with
/// `matchedGeometryEffect`, not a splash handing off to a second screen.
///
/// Tapping the key plays the ignition: the cap wipes green left-to-right, its label morphs to
/// "let's go", and the lone chevron blooms into a three-chevron march. Then the whole intro zooms
/// through and dissolves.
///
/// Ported from the previous app, with two deliberate differences: the resting chevron no longer
/// shifts when the other two emerge (see ``DesignSystem/ChevronRun``), and there is no
/// "already seen this" branch yet — that needs somewhere to persist the flag and something to
/// show instead, neither of which exists.
public struct WelcomeView: View {
    private let onFinished: () -> Void

    public init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    @Namespace private var glyph

    /// Reduce Motion quiets the ignition flourish — the chevron emerge is positional (WCAG 2.3.3).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// false = the mark rests centered (splash); true = it has settled into its slot above the name.
    @State private var atWelcome = false
    /// The name, tagline and key fade in as the mark settles.
    @State private var contentVisible = false
    /// The tap has fired: green wipe, label morph, chevron march.
    @State private var launching = false
    /// Which chevron is lit as the highlight travels left→right.
    @State private var chevronActive = 0
    /// The final dive — the intro scales up and dissolves.
    @State private var divingIn = false
    @State private var launchTask: Task<Void, Never>?

    /// The mark is 72pt centered on the splash and 64pt in its welcome slot. The font stays fixed
    /// because `font` cannot be interpolated; `scaleEffect` carries the size change so the move
    /// reads as one continuous glide.
    private let welcomeScale: CGFloat = 64.0 / 72.0

    public var body: some View {
        ZStack {
            Color.ppBackground.ignoresSafeArea()

            welcomeLayout

            // The splash slot: dead center of the screen.
            Color.clear
                .frame(width: 2, height: 2)
                .matchedGeometryEffect(
                    id: Self.glyphSlot, in: glyph, properties: .position, isSource: !atWelcome
                )

            // The one true mark, following whichever slot is currently the source.
            Text(Self.mark)
                .font(.ppMark)
                .foregroundStyle(Color.ppAccent)
                .scaleEffect(atWelcome ? welcomeScale : 1)
                .matchedGeometryEffect(
                    id: Self.glyphSlot, in: glyph, properties: .position, isSource: false
                )
                .accessibilityHidden(true)
        }
        .scaleEffect(divingIn ? 1.12 : 1)
        .opacity(divingIn ? 0 : 1)
        .task { await settle() }
        .onDisappear { launchTask?.cancel() }
    }

    private static let mark = "++"
    private static let glyphSlot = "glyphSlot"

    private var welcomeLayout: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: Spacing.md - 2) {
                // Invisible twin: reserves the welcome slot so the real mark has somewhere to fly
                // to. Never drawn, never spoken.
                Text(Self.mark)
                    .font(.ppMark)
                    .scaleEffect(welcomeScale)
                    .opacity(0)
                    .matchedGeometryEffect(
                        id: Self.glyphSlot, in: glyph, properties: .position, isSource: atWelcome
                    )
                    .accessibilityHidden(true)

                Text("PlusPlus")
                    .font(.ppTitle)
                    .foregroundStyle(Color.ppTextPrimary)

                Text("A hackable workout tracker for incrementing yourself")
                    .font(.ppSubheadline)
                    .foregroundStyle(Color.ppTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.xl + Spacing.xs)
            .opacity(contentVisible ? 1 : 0)

            Spacer()

            startButton
                .opacity(contentVisible ? 1 : 0)
        }
        // `opacity(0)` does not remove a view from hit testing. Without this, an invisible
        // "Start building" sits tappable through the entire splash dwell, so a stray tap fires the
        // ignition — two haptics and an entry down the wrong path — before the key is even visible.
        .allowsHitTesting(contentVisible)
        // Lay out against the full display, not the safe area. In the app this was lifted from,
        // the intro was an overlay on a TabView, whose frame already ran edge to edge — so the
        // mark centered on the display and the key measured its inset from the physical bottom.
        // Standing alone it has to say so, and it has to say so for BOTH edges: honoring just
        // the bottom leaves the whole content block sitting ~30pt low, because half the top
        // inset lands in the spacer above it.
        .ignoresSafeArea()
    }

    private var startButton: some View {
        Button(action: beginLaunch) {
            HStack(spacing: Spacing.sm) {
                // Reserve the width of the LONGER label so swapping "Start building" for
                // "let's go" cannot change the text box's width and shove the chevrons. A hidden
                // placeholder fixes the box, and the live label rides inside it centered — so the
                // shorter label lands on the same center the longer one had, and the morph reads
                // as one word replacing another in place rather than sliding.
                Text(Self.restingLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .hidden()
                    .overlay {
                        Text(launching ? Self.launchingLabel : Self.restingLabel)
                            .contentTransition(.opacity)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }

                ChevronRun(isRunning: launching, activeIndex: chevronActive)
            }
            .font(.ppButtonLabel)
            .foregroundStyle(Color.ppOnPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .background {
                // The commit wipe: green fills left-to-right across the cap.
                ZStack(alignment: .leading) {
                    Color.ppPrimaryFill
                    Color.ppAccent
                        .scaleEffect(x: launching ? 1 : 0, anchor: .leading)
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
            }
        }
        .buttonStyle(.raisedPrimaryKey(cornerRadius: Radius.xl))
        .disabled(launching)
        .accessibilityIdentifier("welcomeStartButton")
        // Equal side and bottom insets, so the key's corners echo the display's and it sits up
        // near where the screen starts to curve rather than pinned to the very bottom.
        .padding(.horizontal, Spacing.screenEdge)
        .padding(.bottom, Spacing.screenEdge)
    }

    private static let restingLabel: LocalizedStringKey = "Start building"
    private static let launchingLabel: LocalizedStringKey = "let's go"

    /// Hold on the mark, then settle it into the welcome slot and fade the content in.
    private func settle() async {
        try? await Task.sleep(for: .seconds(0.9))
        guard !Task.isCancelled else { return }

        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            atWelcome = true
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.12)) {
            contentVisible = true
        }
    }

    /// The ignition: wipe, morph, chevron march, dive.
    private func beginLaunch() {
        guard !launching else { return }

        impact()
        withAnimation(.easeInOut(duration: 0.32)) {
            launching = true
        }

        launchTask = Task { @MainActor in
            if reduceMotion {
                // No march: just hold a beat so the green wipe registers before the dive.
                try? await Task.sleep(for: .seconds(0.5))
                guard !Task.isCancelled else { return }
            } else {
                // Let the wipe land and the extra chevrons emerge before the highlight travels.
                try? await Task.sleep(for: .seconds(0.32))
                guard !Task.isCancelled else { return }

                // Two passes left→right, ending on the rightmost chevron.
                for hop in 0..<(ChevronRun.count * 2) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        chevronActive = hop % ChevronRun.count
                    }
                    try? await Task.sleep(for: .seconds(0.15))
                    guard !Task.isCancelled else { return }
                }
            }

            success()
            withAnimation(.easeIn(duration: 0.3)) {
                divingIn = true
            }
            try? await Task.sleep(for: .seconds(0.28))
            guard !Task.isCancelled else { return }
            onFinished()
        }
    }

    private func impact() {
        #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    /// The commit "thud", landing as the dive kicks off.
    private func success() {
        #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

#Preview {
    WelcomeView {}
}
