import SwiftUI

/// A drawer under the screen: opening it slides the screen right, leaving a sliver of it in
/// view. A swipe in from the left edge opens it, following the finger; a tap on the sliver, a
/// swipe left, or VoiceOver's escape closes it. With Reduce Motion the screen moves at once and
/// the drawer fades in beside it, or out before it moves back.
/// The screen darkens as the drawer opens. A haptic plays the moment the drawer starts to open,
/// and another, firmer, the moment it starts to shut; a swipe plays one only as it is let go,
/// and a swipe that springs back to where it began plays none.
///
/// Whoever keeps `isOpen` may refuse an open: the drawer then goes back closed, never resting
/// open over a screen that reads it shut. `isHeld` is true while a finger holds the drawer, so
/// what keeps it can treat a swipe under way as the drawer asked for.
///
/// The drawer is in the hierarchy only while it shows, so what it holds, a pushed screen
/// included, starts fresh each time it opens.
public struct SideDrawer<Drawer: View, Content: View>: View {
    @Binding private var isOpen: Bool
    @Binding private var isHeld: Bool
    /// Whether a swipe in from the left edge opens the drawer, off where the edge goes back.
    private let swipeOpens: Bool
    private let drawer: Drawer
    private let content: Content
    /// How far open, 0 to 1, fixed for a snapshot; nil follows `isOpen` and the finger.
    private let fixedProgress: CGFloat?

    /// How far open the drawer is going: 0 or 1 from the moment a slide starts (with Reduce
    /// Motion, as a fade ends), and the finger's place during a swipe. What is drawn while a
    /// slide runs is `drawn`.
    @State private var heading: CGFloat
    /// Where the drawer is going, so a change of `isOpen` that a swipe made doesn't move it twice;
    /// a change of it plays the haptic.
    @State private var target: Bool
    @State private var isDrawerInView: Bool
    /// How far open the drawer was as the swipe following the finger began; nil with none.
    @State private var swipeStart: CGFloat?
    /// How far open the drawer is drawn, mid-settle included, where a swipe starts from.
    @State private var drawn: DrawnProgress
    /// The drawer faded out, with Reduce Motion, before it fades in or once it has faded out:
    /// an opacity transition faded it in but, on removal, dropped it in one frame.
    @State private var isDrawerFaded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        isOpen: Binding<Bool>,
        isHeld: Binding<Bool> = .constant(false),
        swipeOpens: Bool = true,
        @ViewBuilder drawer: () -> Drawer,
        @ViewBuilder content: () -> Content,
    ) {
        self.init(
            isOpen: isOpen,
            isHeld: isHeld,
            swipeOpens: swipeOpens,
            progress: nil,
            drawer: drawer,
            content: content,
        )
    }

    init(
        isOpen: Binding<Bool>,
        isHeld: Binding<Bool> = .constant(false),
        swipeOpens: Bool = true,
        progress: CGFloat?,
        @ViewBuilder drawer: () -> Drawer,
        @ViewBuilder content: () -> Content,
    ) {
        _isOpen = isOpen
        _isHeld = isHeld
        self.swipeOpens = swipeOpens
        fixedProgress = progress
        let open = isOpen.wrappedValue || (progress ?? 0) > 0
        let heading = progress ?? (isOpen.wrappedValue ? 1 : 0)
        _heading = State(initialValue: heading)
        _drawn = State(initialValue: DrawnProgress(value: heading))
        _target = State(initialValue: isOpen.wrappedValue)
        _isDrawerInView = State(initialValue: open)
        self.drawer = drawer()
        self.content = content()
    }

    public var body: some View {
        let progress = fixedProgress ?? heading
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
                    .modifier(DrawerSlide(progress: progress, width: drawerWidth, drawn: drawn))
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
    }

    /// Moves the drawer with a swipe, and settles it where the swipe leaves it.
    private func follow(_ phase: DrawerDrag.Phase, width: CGFloat) {
        switch phase {
        case let .changed(translation):
            if !isHeld {
                isHeld = true
            }
            // With Reduce Motion nothing follows the finger: the release fades.
            guard !reduceMotion else { return }
            let start = swipeStart ?? drawn.value
            swipeStart = start
            isDrawerInView = true
            let progress = DrawerDrag.progress(translation: translation, width: width, from: start)
            withTransaction(Transaction(animation: nil)) { heading = progress }
        case let .ended(translation, velocity):
            isHeld = false
            let start = swipeStart ?? drawn.value
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
            isHeld = false
            swipeStart = nil
            settle(open: isOpen)
        }
    }

    /// Slides the drawer open or closed, leaving at `speed` (lengths of its way a second). With
    /// Reduce Motion only opacity animates: opening, the screen and its dim take their place
    /// beside the drawer at once and the drawer fades in; closing, the drawer fades out and the
    /// screen goes back once it has. An open that `isOpen`'s keeper refuses settles closed.
    private func settle(open asked: Bool, speed asSwiped: CGFloat = 0) {
        let open = settledSide(asking: asked, of: $isOpen)
        // A release toward an open that was refused springs back from rest.
        let speed = open == asked ? asSwiped : 0
        target = open
        isDrawerInView = true
        let end: CGFloat = open ? 1 : 0
        guard !reduceMotion else {
            // A swipe that leaves the drawer open, where it already shows, changes nothing.
            if open, heading != end || isDrawerFaded {
                withTransaction(Transaction(animation: nil)) {
                    isDrawerFaded = true
                    heading = end
                }
            }
            withAnimation(DrawerMetrics.fade) { isDrawerFaded = !open } completion: {
                if open == target {
                    heading = end
                }
                rest(open: open)
            }
            return
        }
        let animation = Animation.interpolatingSpring(DrawerMetrics.slide, initialVelocity: speed)
        withAnimation(animation) { heading = end } completion: { rest(open: open) }
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

/// The side a drawer asked to settle `open` comes to rest on: what `isOpen` holds once asked.
/// Its keeper may refuse an open, as the workout's session does once a row's sheet has been
/// asked for; a drawer that settled where it was asked then rested open, drawn over a screen that
/// read it shut, its title and swipe dead.
func settledSide(asking open: Bool, of isOpen: Binding<Bool>) -> Bool {
    isOpen.wrappedValue = open
    return isOpen.wrappedValue
}

/// How far open a `SideDrawer` is drawn, written as each frame is drawn and read only as a
/// swipe begins, so it is a plain reference: a change to it redraws nothing.
final class DrawnProgress {
    var value: CGFloat

    init(value: CGFloat) {
        self.value = value
    }
}

/// Slides the screen aside by how far open the drawer is, and records that progress as each
/// frame draws it, a settle's spring included. It draws the offset itself: a modifier that only
/// passed its content through had its body skipped, so it recorded nothing as the spring ran.
struct DrawerSlide: ViewModifier, Animatable {
    var progress: CGFloat
    let width: CGFloat
    let drawn: DrawnProgress

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        drawn.value = progress
        return content.offset(x: progress * width)
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

/// Going to a place by way of the drawer: the mark of the place showing slides to the place
/// chosen, and the drawer closes as it lands, so the change is seen before the drawer goes. A
/// drawer row tapped starts at the slide; Log's Go to Workouts first opens the drawer with its
/// own motion. The beats a keeper of the drawer sleeps to, from the start.
public enum DrawerWay {
    /// When the drawer's opening has visibly arrived: its slide's duration, after which the
    /// spring's tail is too small to see, or with Reduce Motion its fade's.
    public static func arrival(reduceMotion: Bool) -> Duration {
        .seconds(reduceMotion ? DrawerMetrics.fadeDuration : DrawerMetrics.slide.duration)
    }

    /// A drawer opened for the person, not by them, is held open longer, at the ++ button's
    /// pace both ways, long enough to read where the mark was and where it went: `holdBefore`
    /// with the mark still on the place showing once the opening has arrived, and `holdAfter`
    /// with it on the new place once it has landed, before the close. A drawer row tapped holds
    /// neither: the person chose, and the drawer closes as the mark arrives.
    public static let holdBefore = Duration.milliseconds(200)
    public static let holdAfter = Duration.milliseconds(300)
    /// On every way, a row tapped included: the mark rests on its new place this long before the
    /// drawer closes, on top of `holdAfter` where the drawer was opened for the person. Closing
    /// as the mark arrived read as too fast (Dave, 2026-11-23). The mark's own slide is unchanged.
    public static let landedHold = Duration.milliseconds(200)

    /// How long the mark takes to visibly arrive at its new place, which the drawer waits for
    /// before closing: the slide's duration, not its settle, whose tail is too small to see.
    /// With Reduce Motion the mark changes rows at once and the drawer waits a moment so the
    /// change is seen.
    public static func markWait(reduceMotion: Bool) -> Duration {
        .seconds(reduceMotion ? markPause : markSlideDuration)
    }

    /// The mark sliding from one place to the next: easing in, so it is seen to leave its row,
    /// then quick through the middle and landing softly, stopping dead. On `.snappy` it was off
    /// the mark at full speed, and eased evenly in and out it felt soft. Nil with Reduce Motion:
    /// it changes rows at once.
    public static func markSlide(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .timingCurve(0.5, 0, 0.2, 1, duration: markSlideDuration)
    }

    private static let markSlideDuration = 0.25
    /// With Reduce Motion, the new mark held in view before the drawer closes.
    private static let markPause = 0.2
}

enum DrawerMetrics {
    /// How much of the screen stays in view beside the open drawer.
    static let sliver: CGFloat = 78
    /// The shadow the screen casts on the drawer: a hint of depth at its trailing edge.
    static let shadowRadius: CGFloat = 10
    static let shadowOffset: CGFloat = -6
    /// Opening and closing: quick and without bounce, as a key answers a tap.
    static let slide = Spring(duration: 0.25, bounce: 0)
    /// The drawer fading in or out, with Reduce Motion.
    static let fade = Animation.easeInOut(duration: fadeDuration)
    static let fadeDuration = 0.2
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
