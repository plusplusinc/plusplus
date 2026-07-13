import SwiftUI
import Observation
import UIKit

/// Drives the slide-to-reveal drawer (the top-left ++ surface): the whole
/// app (tab bar and all) slides right, uncovering the app-level
/// `RevealSurface` beneath and leaving a thin peeking sliver of the app on
/// the right — the Claude-drawer interaction model. Lives above the tabs'
/// NavigationStacks so it moves the entire `TabView` as one layer.
@Observable @MainActor
final class RevealController {
    /// 0 = app fully covering the surface, 1 = surface fully revealed.
    /// Drives every transform; animated on a snap, bound 1:1 while dragging.
    var openFraction: CGFloat = 0

    /// True only while a finger is dragging the app layer — suppresses the
    /// snap spring so the app tracks the finger directly.
    private(set) var dragging = false
    private var dragStart: CGFloat = 0

    /// The snapped state: past halfway reads as open.
    var isOpen: Bool { openFraction > 0.5 }

    /// Horizontal travel as a fraction of screen width. The app slides
    /// side-to-side with no scaling (Dave, build 63 feedback: scaling made
    /// the tab bar wobble vertically and clipped the peeking ++), so the
    /// peek is the remaining ~20% at full open.
    static let travelFactor: CGFloat = 0.8

    // MARK: - Swipe-to-open gating (root views only)

    /// Raw value of the active tab; set by RootTabView.
    var activeTab = "today"
    /// Per-tab "is this tab's NavigationStack at its root?", reported by
    /// each root view. Swipe-to-open is allowed only at a root, where there
    /// is no pushed screen whose full-width swipe-back the edge drag would
    /// fight.
    var tabRootState: [String: Bool] = [:]
    var canSwipeOpen: Bool { tabRootState[activeTab] ?? true }

    /// A soft tap on every commit to open or closed.
    private let impact = UIImpactFeedbackGenerator(style: .medium)

    func toggle() { setOpen(!isOpen) }
    func open() { setOpen(true) }
    func close() { setOpen(false) }

    private func setOpen(_ open: Bool) {
        let target: CGFloat = open ? 1 : 0
        // Only when actually moving to a new state (not re-closing a closed
        // drawer), so an aborted flick that barely moved stays quiet.
        if abs(openFraction - target) > 0.01 { impact.impactOccurred() }
        // Snappy + confident: fast response, damped just short of a bounce.
        // Under Reduce Motion the whole-app slide would be large vestibular
        // motion, so it resolves to an instant state change (WCAG 2.3.3).
        withAnimation(Theme.Anim.flourish(.spring(response: 0.33, dampingFraction: 0.86))) {
            openFraction = target
        }
    }

    // MARK: - Dragging (drag the peeking app back to close / edge to open)

    func beginDrag() {
        dragStart = openFraction
        dragging = true
        impact.prepare()
    }

    func updateDrag(translationX: CGFloat, width: CGFloat) {
        let travel = max(width * Self.travelFactor, 1)
        openFraction = min(1, max(0, dragStart + translationX / travel))
    }

    /// Snap using the velocity-aware PROJECTED landing, not just where the
    /// finger stopped — a quick flick opens even if it didn't travel far
    /// (Dave, build 64: flicks were opening partway then aborting). Biased
    /// slightly toward opening.
    func endDrag(predictedTranslationX: CGFloat, width: CGFloat) {
        dragging = false
        let travel = max(width * Self.travelFactor, 1)
        let projected = dragStart + predictedTranslationX / travel
        setOpen(projected > 0.35)
    }
}

/// Wraps the app (the `TabView`) as a movable top layer over `RevealSurface`.
/// The app slides right by 0.8W (no scaling), rounding its left corners with
/// a drop shadow and a dim/lighten veil fading in over it; the surface
/// beneath stays static.
struct RevealContainer<Content: View>: View {
    let controller: RevealController
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            let f = controller.openFraction
            let width = geo.size.width
            ZStack {
                // The surface, beneath — sits STATICALLY (Dave, build 64: no
                // parallax/fade); the app simply slides off it.
                RevealSurface()
                    .frame(width: geo.size.width, height: geo.size.height)
                    // Only interactive once substantially revealed; the app
                    // covers it otherwise.
                    .allowsHitTesting(controller.isOpen)
                    // Kept out of the VoiceOver tree while the app covers it,
                    // so focus can't land on the hidden surface (a11y audit).
                    .accessibilityHidden(!controller.isOpen)

                // The app, on top — the whole TabView slides right as one
                // layer (no scaling). Rounded left corners + a drop shadow
                // give it the sliding-card read.
                content
                    .overlay { closeScrim(fraction: f, width: width) }
                    .clipShape(RoundedRectangle(cornerRadius: f * 34, style: .continuous))
                    .shadow(color: .black.opacity(0.55 * f), radius: 28, x: 0, y: 22)
                    .offset(x: f * width * RevealController.travelFactor)
                    // While the drawer is open the covered app is inert to
                    // VoiceOver; the surface beneath owns focus.
                    .accessibilityHidden(controller.isOpen)

                // Swipe-to-open: a stationary left-edge strip, present only
                // at a tab root (no pushed screen whose swipe-back this would
                // fight). Stays mounted while a drag is live (|| dragging) so
                // a full-throw open can't unmount it mid-gesture and skip
                // endDrag. Inset below the header so it never swallows a tap
                // on the ++ key; thin so it barely overlaps row content.
                if controller.canSwipeOpen && (f < 0.999 || controller.dragging) {
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: 16)
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .gesture(openDrag(width: width))
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 104)
                }
            }
            .environment(controller)
            // Move VoiceOver focus onto whichever layer just took over
            // (surface on open, app on close).
            .onChange(of: controller.isOpen) { _, _ in
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            }
        }
        .ignoresSafeArea()
    }

    /// The dim layer over the peeking app: fades in with the reveal, and
    /// once open catches a tap (close) or a leftward drag (drag-to-close).
    /// Inert while closed so the app underneath stays fully interactive.
    private func closeScrim(fraction f: CGFloat, width: CGFloat) -> some View {
        Rectangle()
            // Darken the covered app in dark mode, LIGHTEN it in light mode
            // (Dave, build 64) — a dark veil over a light UI read wrong.
            .fill(Color(light: 0xFFFFFF, dark: 0x000000).opacity(0.42 * f))
            .ignoresSafeArea()
            .allowsHitTesting(f > 0.02)
            .onTapGesture { controller.close() }
            .gesture(revealDrag(width: width))
    }

    /// One drag recognizer for both directions. Measured in GLOBAL space —
    /// the gesture rides a layer the drawer itself moves, so a local
    /// translation would feed back on the value it's driving and jitter
    /// wildly (Dave, build 63). Global space is fixed to the screen and
    /// breaks that loop.
    private func revealDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                if !controller.dragging { controller.beginDrag() }
                controller.updateDrag(translationX: value.translation.width, width: width)
            }
            .onEnded { value in
                controller.endDrag(predictedTranslationX: value.predictedEndTranslation.width, width: width)
            }
    }

    /// The open strip sits over the leftmost column of scrollable rows, so it
    /// only engages on a rightward, horizontal-dominant intent — a vertical
    /// scroll or a leftward row-swipe started at the edge never moves the
    /// drawer. Once engaged it tracks like any drag.
    private func openDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                if !controller.dragging {
                    guard value.translation.width > 0,
                          abs(value.translation.width) > abs(value.translation.height)
                    else { return }
                    controller.beginDrag()
                }
                controller.updateDrag(translationX: value.translation.width, width: width)
            }
            .onEnded { value in
                if controller.dragging {
                    controller.endDrag(predictedTranslationX: value.predictedEndTranslation.width, width: width)
                }
            }
    }
}

private struct RevealRootReporter: ViewModifier {
    let tab: String
    let atRoot: Bool
    @Environment(RevealController.self) private var reveal

    func body(content: Content) -> some View {
        content.onChange(of: atRoot, initial: true) { _, isRoot in
            reveal.tabRootState[tab] = isRoot
        }
    }
}

extension View {
    /// A root tab view reports whether its NavigationStack is at the root,
    /// so the reveal drawer only offers swipe-to-open there (a pushed
    /// screen owns the left edge for its swipe-back).
    func revealRoot(tab: String, atRoot: Bool) -> some View {
        modifier(RevealRootReporter(tab: tab, atRoot: atRoot))
    }
}
