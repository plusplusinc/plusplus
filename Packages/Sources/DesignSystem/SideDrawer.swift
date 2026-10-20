import SwiftUI

/// A drawer under the screen: opening it slides the screen right, leaving a sliver of it in
/// view. A swipe in from the left edge opens it, following the finger; a tap on the sliver, a
/// swipe left, or VoiceOver's escape closes it. With Reduce Motion it fades rather than slides.
/// The screen darkens as the drawer opens, and a haptic plays each time it comes to rest open or
/// closed; a swipe that springs back to where it began plays none.
///
/// The drawer is in the hierarchy only while it shows, so what it holds, a pushed screen
/// included, starts fresh each time it opens.
public struct SideDrawer<Drawer: View, Content: View>: View {
    @Binding private var isOpen: Bool
    private let drawer: Drawer
    private let content: Content
    /// How far open, 0 to 1, fixed for a snapshot; nil follows `isOpen` and the finger.
    private let fixedProgress: CGFloat?

    /// How far open the drawer is drawn: settles to 0 or 1, and follows a swipe in between.
    @State private var shown: CGFloat
    /// Where the drawer is going, so a change of `isOpen` that a swipe made doesn't move it twice.
    @State private var target: Bool
    @State private var isDrawerInView: Bool
    /// How far open the drawer was as the swipe following the finger began; nil with none.
    @State private var swipeStart: CGFloat?
    /// The screen faded out, with Reduce Motion, while it moves unseen.
    @State private var isContentFaded = false
    /// Where the drawer last came to rest, which the haptics follow.
    @State private var restsOpen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObserveHotReload private var hotReload

    public init(
        isOpen: Binding<Bool>,
        @ViewBuilder drawer: () -> Drawer,
        @ViewBuilder content: () -> Content,
    ) {
        self.init(isOpen: isOpen, progress: nil, drawer: drawer, content: content)
    }

    init(
        isOpen: Binding<Bool>,
        progress: CGFloat?,
        @ViewBuilder drawer: () -> Drawer,
        @ViewBuilder content: () -> Content,
    ) {
        _isOpen = isOpen
        fixedProgress = progress
        let open = isOpen.wrappedValue || (progress ?? 0) > 0
        _shown = State(initialValue: progress ?? (isOpen.wrappedValue ? 1 : 0))
        _target = State(initialValue: isOpen.wrappedValue)
        _restsOpen = State(initialValue: isOpen.wrappedValue)
        _isDrawerInView = State(initialValue: open)
        self.drawer = drawer()
        self.content = content()
    }

    public var body: some View {
        let progress = fixedProgress ?? shown
        GeometryReader { proxy in
            let drawerWidth = max(proxy.size.width - DrawerMetrics.sliver, 0)
            ZStack(alignment: .leading) {
                // Behind the sliver while the screen fades, with Reduce Motion.
                Color.pp(.background).ignoresSafeArea()
                if isDrawerInView {
                    drawer
                        .frame(width: drawerWidth)
                        .background { Color.pp(.background).ignoresSafeArea() }
                        .accessibilityAddTraits(.isModal)
                        .accessibilityAction(.escape) { isOpen = false }
                }
                content
                    .frame(width: proxy.size.width)
                    .allowsHitTesting(!isOpen && swipeStart == nil)
                    .accessibilityHidden(isOpen)
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
                    .opacity(isContentFaded ? 0 : 1)
                    .offset(x: progress * drawerWidth)
            }
            #if os(iOS)
            .gesture(DrawerSwipe(opens: true, isEnabled: !isOpen) { phase in
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
        .sensoryFeedback(trigger: restsOpen) { _, open in
            open ? DrawerMetrics.opened : DrawerMetrics.closed
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

    /// Slides the drawer open or closed, leaving at `speed` (lengths of its way a second), or
    /// with Reduce Motion fades the screen out, moves it, and fades it back in.
    private func settle(open: Bool, speed: CGFloat = 0) {
        target = open
        isOpen = open
        isDrawerInView = true
        let end: CGFloat = open ? 1 : 0
        guard !reduceMotion else {
            withAnimation(DrawerMetrics.fade) { isContentFaded = true } completion: {
                shown = end
                withAnimation(DrawerMetrics.fade) { isContentFaded = false } completion: {
                    rest(open: open)
                }
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
        restsOpen = open
        if !open {
            isDrawerInView = false
        }
    }
}

enum DrawerMetrics {
    /// How much of the screen stays in view beside the open drawer.
    static let sliver: CGFloat = 78
    /// The shadow the screen casts on the drawer, from the design.
    static let shadowRadius: CGFloat = 18
    static let shadowOffset: CGFloat = -14
    /// Opening and closing: quick, as it answers a tap.
    static let slide = Spring.snappy(duration: 0.3)
    /// Each half of the Reduce Motion cross-fade, out and back in.
    static let fade = Animation.snappy(duration: 0.1)
    /// Coming to rest open, and closed: soft, as a panel settling, with closing the lighter.
    static let opened = SensoryFeedback.impact(flexibility: .soft, intensity: 0.8)
    static let closed = SensoryFeedback.impact(flexibility: .soft, intensity: 0.5)
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
