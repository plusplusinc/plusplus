import SwiftUI

/// A drawer under the screen: opening it slides the screen right, leaving a sliver of it in
/// view. A swipe in from the left edge opens it, following the finger; a tap on the sliver, a
/// swipe left, or VoiceOver's escape closes it. With Reduce Motion the screen moves at once and
/// the drawer fades in beside it, or out before it moves back.
/// The screen darkens as the drawer opens. A haptic plays the moment the drawer starts to open,
/// and another, firmer, the moment it starts to shut; a swipe plays one only as it is let go,
/// and a swipe that springs back to where it began plays none.
///
/// The drawer is in the hierarchy only while it shows, so what it holds, a pushed screen
/// included, starts fresh each time it opens.
public struct SideDrawer<Drawer: View, Content: View>: View {
    @Binding private var isOpen: Bool
    /// Whether a swipe in from the left edge opens the drawer, off where the edge goes back.
    private let swipeOpens: Bool
    private let drawer: Drawer
    private let content: Content
    /// How far open, 0 to 1, fixed for a snapshot; nil follows `isOpen` and the finger.
    private let fixedProgress: CGFloat?

    /// How far open the drawer is drawn: settles to 0 or 1, and follows a swipe in between.
    @State private var shown: CGFloat
    /// Where the drawer is going, so a change of `isOpen` that a swipe made doesn't move it twice;
    /// a change of it plays the haptic.
    @State private var target: Bool
    @State private var isDrawerInView: Bool
    /// How far open the drawer was as the swipe following the finger began; nil with none.
    @State private var swipeStart: CGFloat?
    /// The drawer faded out, with Reduce Motion, before it fades in or once it has faded out:
    /// an opacity transition faded it in but, on removal, dropped it in one frame.
    @State private var isDrawerFaded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    public init(
        isOpen: Binding<Bool>,
        swipeOpens: Bool = true,
        @ViewBuilder drawer: () -> Drawer,
        @ViewBuilder content: () -> Content,
    ) {
        self.init(
            isOpen: isOpen, swipeOpens: swipeOpens, progress: nil, drawer: drawer, content: content,
        )
    }

    init(
        isOpen: Binding<Bool>,
        swipeOpens: Bool = true,
        progress: CGFloat?,
        @ViewBuilder drawer: () -> Drawer,
        @ViewBuilder content: () -> Content,
    ) {
        _isOpen = isOpen
        self.swipeOpens = swipeOpens
        fixedProgress = progress
        let open = isOpen.wrappedValue || (progress ?? 0) > 0
        _shown = State(initialValue: progress ?? (isOpen.wrappedValue ? 1 : 0))
        _target = State(initialValue: isOpen.wrappedValue)
        _isDrawerInView = State(initialValue: open)
        self.drawer = drawer()
        self.content = content()
    }

    public var body: some View {
        let progress = fixedProgress ?? shown
        GeometryReader { proxy in
            let drawerWidth = max(proxy.size.width - DrawerMetrics.sliver, 0)
            ZStack(alignment: .leading) {
                // Behind the drawer while it fades, with Reduce Motion.
                Color.pp(.background).ignoresSafeArea()
                if isDrawerInView {
                    drawer
                        .frame(width: drawerWidth)
                        .background { Color.pp(.background).ignoresSafeArea() }
                        .opacity(isDrawerFaded ? 0 : 1)
                        .accessibilityAddTraits(.isModal)
                        .accessibilityAction(.escape) { isOpen = false }
                }
                content
                    .frame(width: proxy.size.width)
                    .allowsHitTesting(!isOpen && swipeStart == nil)
                    .accessibilityHidden(isOpen)
                    // The screen's bars, hosted apart from it, take their part from here.
                    .environment(\.isBehindOpenDrawer, isOpen)
                    // UIKit lists scroll bars for VoiceOver apart from the content.
                    .scrollIndicators(isOpen ? .hidden : .automatic)
                    .background {
                        Color.pp(.background)
                            .shadow(
                                color: .pp(.shadow).opacity(progress),
                                radius: DrawerMetrics.shadowRadius,
                                x: DrawerMetrics.shadowOffset,
                            )
                            .ignoresSafeArea()
                    }
                    .overlay {
                        Color.pp(.dim)
                            .opacity(progress)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    .overlay {
                        if isOpen {
                            Color.clear
                                .contentShape(.rect)
                                .ignoresSafeArea()
                                .onTapGesture { isOpen = false }
                                .accessibilityHidden(true)
                        }
                    }
                    .offset(x: progress * drawerWidth)
            }
            // Played as the drawer starts toward a new side: `target` changes only then, so a
            // swipe that springs back, or a finger still dragging, plays nothing.
            .sensoryFeedback(trigger: target) { _, open in
                open ? DrawerMetrics.opened : DrawerMetrics.closed
            }
            #if os(iOS)
            .gesture(DrawerSwipe(opens: true, isEnabled: swipeOpens && !isOpen) { phase in
                follow(phase, width: drawerWidth)
            })
            .gesture(DrawerSwipe(opens: false, isEnabled: isOpen) { phase in
                follow(phase, width: drawerWidth)
            })
            #endif
        }
        .onChange(of: isOpen) { _, open in
            if open != target {
                settle(open: open)
            }
        }
        .hotReloadable()
    }

    /// Moves the drawer with a swipe, and settles it where the swipe leaves it.
    private func follow(_ phase: DrawerDrag.Phase, width: CGFloat) {
        switch phase {
        case let .changed(translation):
            // With Reduce Motion nothing follows the finger: the release fades.
            guard !reduceMotion else { return }
            let start = swipeStart ?? shown
            swipeStart = start
            isDrawerInView = true
            let progress = DrawerDrag.progress(translation: translation, width: width, from: start)
            withTransaction(Transaction(animation: nil)) { shown = progress }
        case let .ended(translation, velocity):
            let start = swipeStart ?? shown
            swipeStart = nil
            if reduceMotion {
                settle(open: DrawerDrag.swipeOpens(translation: translation, fromOpen: isOpen))
                return
            }
            let progress = DrawerDrag.progress(translation: translation, width: width, from: start)
            let opens = DrawerDrag.settlesOpen(progress: progress, velocity: velocity)
            settle(open: opens, speed: DrawerDrag.releaseSpeed(
                velocity: velocity, progress: progress, opens: opens, width: width,
            ))
        case .cancelled:
            swipeStart = nil
            settle(open: isOpen)
        }
    }

    /// Slides the drawer open or closed, leaving at `speed` (lengths of its way a second). With
    /// Reduce Motion only opacity animates: opening, the screen and its dim take their place
    /// beside the drawer at once and the drawer fades in; closing, the drawer fades out and the
    /// screen goes back once it has.
    private func settle(open: Bool, speed: CGFloat = 0) {
        target = open
        isOpen = open
        isDrawerInView = true
        let end: CGFloat = open ? 1 : 0
        guard !reduceMotion else {
            // A swipe that leaves the drawer open, where it already shows, changes nothing.
            if open, shown != end || isDrawerFaded {
                withTransaction(Transaction(animation: nil)) {
                    isDrawerFaded = true
                    shown = end
                }
            }
            withAnimation(DrawerMetrics.fade) { isDrawerFaded = !open } completion: {
                if open == target {
                    shown = end
                }
                rest(open: open)
            }
            return
        }
        let animation = Animation.interpolatingSpring(DrawerMetrics.slide, initialVelocity: speed)
        withAnimation(animation) { shown = end } completion: { rest(open: open) }
    }

    /// Ends a settle: unless another has taken over since, or a finger holds the drawer, the
    /// drawer is at rest, and leaves the hierarchy if closed.
    private func rest(open: Bool) {
        guard open == target, swipeStart == nil else { return }
        if !open {
            isDrawerInView = false
            isDrawerFaded = false
        }
    }
}

extension View {
    /// Leaves VoiceOver while a `SideDrawer` is open beside it, for a control in a bar of the
    /// screen: the navigation bar and a `safeAreaBar` are hosted apart from the screen, out of
    /// reach of the drawer's modal trait and of `accessibilityHidden` on the screen, and they
    /// ignore `accessibilityHidden` on the control too. An empty representation they keep.
    /// `primaryKeyBar` applies it; a toolbar item has to itself.
    public func hiddenBehindDrawer() -> some View {
        modifier(HiddenBehindDrawer())
    }
}

private struct HiddenBehindDrawer: ViewModifier {
    @Environment(\.isBehindOpenDrawer) private var isBehindOpenDrawer

    func body(content: Content) -> some View {
        content.accessibilityRepresentation {
            if !isBehindOpenDrawer {
                content
            }
        }
    }
}

extension EnvironmentValues {
    /// Whether the view is on the screen beside an open `SideDrawer`.
    @Entry var isBehindOpenDrawer = false
}

enum DrawerMetrics {
    /// How much of the screen stays in view beside the open drawer.
    static let sliver: CGFloat = 78
    /// The shadow the screen casts on the drawer, from the design.
    static let shadowRadius: CGFloat = 18
    static let shadowOffset: CGFloat = -14
    /// Opening and closing: quick and without bounce, as a key answers a tap.
    static let slide = Spring(duration: 0.25, bounce: 0)
    /// The drawer fading in or out, with Reduce Motion.
    static let fade = Animation.easeInOut(duration: 0.2)
    /// Starting to open: solid, between soft (muddy) and rigid, and lighter than shutting.
    static let opened = SensoryFeedback.impact(flexibility: .solid, intensity: 0.5)
    /// Starting to shut: solid, as opening is, and firmer, so it's felt as the drawer closes.
    static let closed = SensoryFeedback.impact(flexibility: .solid, intensity: 0.7)
}

#Preview {
    @Previewable @State var isOpen = true
    SideDrawer(isOpen: $isOpen) {
        Text(verbatim: "Drawer")
    } content: {
        Button("Open") { isOpen = true }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
