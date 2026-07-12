import SwiftUI
import Observation

/// Drives the slide-to-reveal drawer (the top-left ++ surface): the whole
/// app (tab bar and all) slides right and scales down, uncovering the
/// app-level `RevealSurface` beneath, leaving a thin peeking sliver of the
/// app on the right — the Claude-drawer interaction model. Lives above the
/// tabs' NavigationStacks so it moves the entire `TabView` as one layer.
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

    func toggle() { setOpen(!isOpen) }
    func open() { setOpen(true) }
    func close() { setOpen(false) }

    private func setOpen(_ open: Bool) {
        withAnimation(.spring(response: 0.44, dampingFraction: 0.9)) {
            openFraction = open ? 1 : 0
        }
    }

    // MARK: - Dragging (drag the peeking app back to close)

    func beginDrag() {
        dragStart = openFraction
        dragging = true
    }

    func updateDrag(translationX: CGFloat, width: CGFloat) {
        let travel = max(width * Self.travelFactor, 1)
        openFraction = min(1, max(0, dragStart + translationX / travel))
    }

    /// Snap on release: past 40% open → open, else → closed (mock threshold).
    func endDrag() {
        dragging = false
        setOpen(openFraction > 0.4)
    }
}

/// Wraps the app (the `TabView`) as a movable top layer over `RevealSurface`.
/// The transform matches the design handoff: translate 0.72W, scale to
/// 0.86, corners to 34 pt, a drop shadow and a dim overlay fading in, while
/// the surface parallaxes in from the left and fades up.
struct RevealContainer<Content: View>: View {
    let controller: RevealController
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            let f = controller.openFraction
            let width = geo.size.width
            ZStack {
                // The surface, beneath — revealed as the app slides away.
                RevealSurface()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .offset(x: (1 - f) * -34)
                    .opacity(0.30 + 0.70 * f)
                    // Only interactive once substantially revealed; the app
                    // covers it otherwise.
                    .allowsHitTesting(controller.isOpen)

                // The app, on top — the whole TabView slides right as one
                // layer (no scaling). Rounded left corners + a drop shadow
                // give it the sliding-card read.
                content
                    .overlay { closeScrim(fraction: f, width: width) }
                    .clipShape(RoundedRectangle(cornerRadius: f * 34, style: .continuous))
                    .shadow(color: .black.opacity(0.55 * f), radius: 28, x: 0, y: 22)
                    .offset(x: f * width * RevealController.travelFactor)

                // Swipe-to-open: a stationary left-edge strip, present only
                // at a tab root (no pushed screen whose swipe-back this would
                // fight). Kept mounted until nearly fully open so it can't
                // vanish out from under an in-progress drag. Inset below the
                // header so it never swallows a tap on the ++ key.
                if controller.canSwipeOpen && f < 0.999 {
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: 20)
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .gesture(revealDrag(width: width))
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 104)
                }
            }
            .environment(controller)
        }
        .ignoresSafeArea()
    }

    /// The dim layer over the peeking app: fades in with the reveal, and
    /// once open catches a tap (close) or a leftward drag (drag-to-close).
    /// Inert while closed so the app underneath stays fully interactive.
    private func closeScrim(fraction f: CGFloat, width: CGFloat) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.42 * f))
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
            .onEnded { _ in controller.endDrag() }
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
