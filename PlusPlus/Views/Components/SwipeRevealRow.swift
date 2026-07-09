import SwiftUI
import SwiftData

/// The one slide-to-reveal affordance, everywhere (#88; Dave reversed
/// #231's brief native experiment — no mixed affordances). The
/// build-31 snap-back is fixed here: a momentum floor keeps a relaxing
/// finger's lift-drift from reading as close-intent, on top of the
/// cancellation-safe live commit. Horizontal-dominant drags reveal;
/// vertical movement stays with the surrounding scroll. One row open
/// at a time via the shared `openRow` binding.
///
/// ⚠️ CONTRACT for content: the row body carries NO tap affordance of
/// its own — no Button, no `onTapGesture`. Build 33's snap-back was a
/// plain Button firing on the finger-lift that ENDED a reveal drag
/// (the card moves with the finger, so the touch never leaves the
/// button's bounds), and its tap-close branch shut the row the drag
/// had just opened. A slop-based tap style failed the same way,
/// CI-proven — the offset chases the finger, so movement relative to
/// the row is ~zero and no slop heuristic can engage. Row activation
/// is `onTap`, which the component composes with the reveal drag in
/// an ExclusiveGesture: once the drag activates (16 pt), the tap is
/// structurally impossible — arbitration, not heuristics.
struct SwipeRevealRow<Content: View, Actions: View>: View {
    let id: PersistentIdentifier
    @Binding var openRow: PersistentIdentifier?
    var enabled: Bool = true
    let actionsWidth: CGFloat
    /// Row activation for a genuine tap (navigate, open a sheet).
    /// While ANY row is open, a tap closes it instead — the one shared
    /// close affordance, owned here rather than copy-pasted into every
    /// consumer's tap handler.
    var onTap: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions

    /// @GestureState, not @State: the system resets it when the touch
    /// sequence is CANCELLED (incoming call, Control Center swipe),
    /// where onEnded never runs — a plain state var left rows frozen
    /// half-swiped (bug hunt finding 3).
    @GestureState private var dragX: CGFloat = 0

    /// The row's resting offset captured at the FIRST drag event, so the
    /// open/closed decision can commit mid-gesture (below) without the
    /// row jumping to the new resting point under the finger.
    @GestureState private var dragBase: CGFloat?

    private var restingOffset: CGFloat {
        openRow == id ? -actionsWidth : 0
    }

    private var offset: CGFloat {
        min(0, max((dragBase ?? restingOffset) + dragX, -actionsWidth - 24))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            actions()
                .frame(width: actionsWidth)
                .frame(maxHeight: .infinity)
                .opacity(offset < -12 ? 1 : 0)
                // opacity(0) does NOT remove a view from hit testing —
                // and inside a List, taps on the row could dispatch to
                // the hidden action button, silently deleting the row
                // (Dave, build 12: "items inexplicably disappear").
                .allowsHitTesting(offset < -12)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.background)
                .offset(x: offset)
                .contentShape(Rectangle())
                // simultaneous with the OUTSIDE world (the List pan must
                // coexist — .gesture starves scrolling, #99); exclusive
                // WITHIN: the drag activating makes the tap impossible.
                .simultaneousGesture(
                    ExclusiveGesture(revealDrag, TapGesture().onEnded { handleTap() })
                )
                .accessibilityAddTraits(onTap != nil ? .isButton : [])
                .accessibilityAction { handleTap() }
        }
        .clipped()
        .animation(.easeOut(duration: 0.18), value: offset)
        // While THIS row is open, the full-width swipe-back stands down:
        // closing a row is a rightward horizontal drag the pop gesture
        // can't distinguish from a back-swipe (#198 review). Balanced on
        // disappear so a pop with a row open can't leak suppression.
        .onChange(of: openRow == id) { _, isOpen in
            PopGestureGate.suppressionCount = max(0, PopGestureGate.suppressionCount + (isOpen ? 1 : -1))
        }
        .onDisappear {
            if openRow == id {
                PopGestureGate.suppressionCount = max(0, PopGestureGate.suppressionCount - 1)
            }
        }
    }

    /// `enabled` gates activation too, mirroring the reveal drag: while
    /// a rail gesture is live, a second finger must neither open sheets
    /// nor close rows.
    private func handleTap() {
        guard enabled else { return }
        if openRow != nil {
            openRow = nil
        } else {
            onTap?()
        }
    }

    private var revealDrag: some Gesture {
        DragGesture(minimumDistance: 16)
            .updating($dragBase) { _, state, _ in
                if state == nil { state = restingOffset }
            }
            .updating($dragX) { value, state, _ in
                guard enabled,
                      abs(value.translation.width) > abs(value.translation.height)
                else { return }
                state = value.translation.width
            }
            // The open/closed decision commits HERE, live at
            // the halfway threshold — not only in onEnded.
            // Inside a List the scroll pan can steal the touch
            // at finger-lift, which CANCELS this gesture:
            // @GestureState resets, onEnded never runs, and a
            // decided-at-end-only row snapped shut under the
            // finger (Dave, build 17: "letting go hides it
            // again"). A cancelled gesture now keeps whatever
            // the drag last crossed.
            .onChanged { value in
                guard enabled,
                      abs(value.translation.width) > abs(value.translation.height),
                      let base = dragBase
                else { return }
                let dragged = base + value.translation.width
                if dragged < -actionsWidth / 2 {
                    if openRow != id { openRow = id }
                } else if openRow == id {
                    openRow = nil
                }
            }
            // onEnded only adds the flick — and only a REAL
            // flick. A relaxing finger drifts a few points
            // rightward at lift; treating that as momentum
            // closed rows the drag had committed open (Dave,
            // build 31: "on release the item snaps back").
            // Below the floor, the live-committed state from
            // onChanged stands. A genuine rightward flick
            // closes WHATEVER row is open — deliberate: a
            // dismissive flick means "close it" regardless
            // of which row it lands on.
            .onEnded { value in
                guard enabled,
                      abs(value.translation.width) > abs(value.translation.height)
                else { return }
                let momentum = value.predictedEndTranslation.width - value.translation.width
                guard abs(momentum) > 36 else { return }
                let projected = (openRow == id ? -actionsWidth : 0) + momentum
                openRow = projected < -actionsWidth / 2 ? id : nil
            }
    }
}

/// One action inside a SwipeRevealRow: 58 pt, mono uppercase label.
struct SwipeActionButton: View {
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 58)
                .frame(maxHeight: .infinity)
                .background(Theme.surface)
                .overlay(Rectangle().frame(width: 1).foregroundStyle(Theme.border), alignment: .leading)
        }
        // Plain, not default: List routes row taps into default-styled
        // buttons anywhere in the row — the second half of the
        // disappearing-rows bug. Safe from the content contract above:
        // this lives in the ACTIONS slot, outside the content gesture,
        // and only receives touches that begin on it while revealed.
        .buttonStyle(.plain)
    }
}
