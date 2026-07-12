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

    /// Horizontal travel is a fraction of the screen width (mock: 0.72W).
    static let travelFactor: CGFloat = 0.72

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

                // The app, on top — the whole TabView moves and scales.
                content
                    .overlay { closeScrim(fraction: f, width: width) }
                    .clipShape(RoundedRectangle(cornerRadius: f * 34, style: .continuous))
                    .shadow(color: .black.opacity(0.55 * f), radius: 28, x: 0, y: 22)
                    .scaleEffect(1 - f * 0.14)
                    .offset(x: f * width * RevealController.travelFactor)
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
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        if !controller.dragging { controller.beginDrag() }
                        controller.updateDrag(translationX: value.translation.width, width: width)
                    }
                    .onEnded { _ in controller.endDrag() }
            )
    }
}
