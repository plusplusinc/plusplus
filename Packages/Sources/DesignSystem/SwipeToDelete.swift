import SwiftUI

/// Where a row swiped left comes to rest when the finger lifts. A full swipe deletes, and with no
/// undo it takes real distance, as the system's does: a drag past most of the row, or a fast swipe
/// whose finger has also traveled well past the Delete key's width. Anything shorter that passes
/// half the key, or is a fast flick, opens the row to show the key; otherwise it closes. Any drag
/// right closes it. `offset` is where the key's leading edge is, starting at the key's width on
/// an open row, and `travel` how far the finger moved; both negative to the left.
enum SwipeSettle: Equatable {
    case closed
    case open
    case delete

    /// A fling, in points per second: faster than a deliberate drag.
    static let flingSpeed: CGFloat = 1000

    /// How far a drag at any speed goes to delete: most of the row, and always well past an open
    /// key, which at the largest text sizes covers more than half the row.
    static func deleteDistance(width: CGFloat, keyWidth: CGFloat) -> CGFloat {
        max(width * 0.6, keyWidth * 1.5)
    }

    static func settle(
        offset: CGFloat,
        travel: CGFloat,
        velocity: CGFloat,
        width: CGFloat,
        keyWidth: CGFloat,
    ) -> Self {
        let distance = -offset
        // Back toward where it came from, at any speed: only an open row can be dragged right.
        if travel > 0 || velocity >= flingSpeed {
            return .closed
        }
        if distance > deleteDistance(width: width, keyWidth: keyWidth) {
            return .delete
        }
        // Speed alone only opens the key: a flick by accident mid-set must not delete.
        if velocity <= -flingSpeed {
            return -travel > keyWidth * 2 ? .delete : .open
        }
        return distance > keyWidth / 2 ? .open : .closed
    }
}

extension View {
    /// Swiping the row left draws a Delete key in from its trailing edge, under the finger;
    /// swiping far enough deletes. The row itself stays put: its names are short and start at
    /// its leading edge, so sliding it would hide the name, and whatever sits beside it, such as
    /// a rail's node, stays on the rail. VoiceOver gets Delete as an action on the row instead.
    ///
    /// `openRow` is which of a list's rows is open, by `id`, so the list keeps one open at a
    /// time and can close it.
    public func swipeToDelete<ID: Hashable>(
        id: ID,
        openRow: Binding<ID?>,
        onDelete: @escaping () -> Void,
    ) -> some View {
        let isOpen = Binding {
            openRow.wrappedValue == id
        } set: { open in
            if open {
                openRow.wrappedValue = id
            } else if openRow.wrappedValue == id {
                openRow.wrappedValue = nil
            }
        }
        return modifier(SwipeToDelete(isOpen: isOpen, onDelete: onDelete))
    }
}

private struct SwipeToDelete: ViewModifier {
    @Binding var isOpen: Bool
    let onDelete: () -> Void

    /// How far the finger has drawn the key in, negative to the left, while it is on the row;
    /// nil at rest.
    @State private var dragOffset: CGFloat?
    @State private var width: CGFloat = 0
    @ScaledMetric(relativeTo: .body) private var keyWidth: CGFloat = 88
    @ObserveHotReload private var hotReload

    /// Where the key's leading edge rests: drawn in by its width when the row is open.
    private var restOffset: CGFloat {
        isOpen ? -keyWidth : 0
    }

    private var offset: CGFloat {
        dragOffset ?? restOffset
    }

    private var pastDelete: Bool {
        -offset > SwipeSettle.deleteDistance(width: width, keyWidth: keyWidth)
    }

    func body(content: Content) -> some View {
        content
            .accessibilityAction(named: "Delete", delete)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                if isOpen {
                    withAnimation { isOpen = false }
                }
            }
            .accessibilityAddTraits(isOpen ? .isButton : [])
            .overlay(alignment: .trailing) { deleteKey }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
            #if os(iOS)
            .gesture(
                HorizontalPan(
                    isOpen: isOpen,
                    onChange: { dragOffset = offset(after: $0) },
                    onEnd: { settle(travel: $0, velocity: $1) },
                    onCancel: { withAnimation(.snappy) { dragOffset = nil } },
                ),
            )
            #endif
            .sensoryFeedback(.impact, trigger: pastDelete) { _, isPast in isPast }
            .hotReloadable()
    }

    @ViewBuilder private var deleteKey: some View {
        if offset < 0 {
            let shape = RoundedRectangle(cornerRadius: Radius.key)
            // At its natural size, from the key's leading edge, so it slides in with the key
            // rather than shrinking to fit.
            Text("Delete")
                .font(.ppButton)
                .foregroundStyle(.pp(.onDestructive))
                .fixedSize()
                .padding(.leading, Spacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                // The key's leading edge follows the finger.
                .frame(width: -offset)
                .background(.pp(.destructive), in: shape)
                .clipShape(shape)
                .contentShape(shape)
                // A UIKit tap, not a Button: a button keeps its touch from touch-down to lift,
                // however far the finger goes, and holds it against the row's pan, so a drag
                // right that began on the key never moved it and deleted on lift. A SwiftUI tap
                // held some drags the same way. A UIKit tap fails once the finger moves a few
                // points, and the pan takes the drag.
                #if os(iOS)
                .gesture(StillTap(action: delete))
                #endif
                .accessibilityRepresentation {
                    Button("Delete", role: .destructive, action: delete)
                }
                .padding(.vertical, Spacing.xs)
                .accessibilityHidden(!isOpen)
        }
    }

    /// Where the key's leading edge is after the finger has moved `translation` from where the
    /// drag began: never right of the row's trailing edge.
    private func offset(after translation: CGFloat) -> CGFloat {
        min(0, restOffset + translation)
    }

    private func settle(travel: CGFloat, velocity: CGFloat) {
        let rest = SwipeSettle.settle(
            offset: offset(after: travel),
            travel: travel,
            velocity: velocity,
            width: width,
            keyWidth: keyWidth,
        )
        guard rest != .delete else { return delete() }
        withAnimation(.snappy) {
            dragOffset = nil
            isOpen = rest == .open
        }
    }

    /// The key covers the row as it goes.
    private func delete() {
        withAnimation(.snappy) {
            dragOffset = -width
            isOpen = false
            onDelete()
        }
    }
}

#if os(iOS)
/// A pan that begins only for a mostly horizontal drag: leftward on a closed row, either way on
/// an open one. Any other drag fails it at once, so a scroll view around the row scrolls as if it
/// were not there, which a SwiftUI drag gesture inside a scroll view cannot promise.
private struct HorizontalPan: UIGestureRecognizerRepresentable {
    let isOpen: Bool
    let onChange: (CGFloat) -> Void
    let onEnd: (_ translation: CGFloat, _ velocity: CGFloat) -> Void
    let onCancel: () -> Void

    func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        // One finger: a second would move the pan's location to between the two.
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_: UIPanGestureRecognizer, context: Context) {
        context.coordinator.isOpen = isOpen
    }

    /// Reports how far the finger has moved across the screen since it touched down, rather than
    /// the pan's translation, which counts from when the pan began. A pan held back behind other
    /// gestures can begin late, after much or all of a quick swipe's travel.
    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let translation = pan.location(in: nil).x - context.coordinator.touchDownX
        switch pan.state {
        case .began, .changed:
            onChange(translation)
        case .ended:
            onEnd(translation, pan.velocity(in: pan.view).x)
        case .cancelled, .failed:
            onCancel()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isOpen = false
        /// Where the finger touched down, in the window.
        var touchDownX: CGFloat = 0

        func gestureRecognizer(_ pan: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if pan.numberOfTouches == 0 {
                touchDownX = touch.location(in: nil).x
            }
            return true
        }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) && (isOpen || velocity.x < 0)
        }
    }
}

/// A tap that fails as soon as the finger moves more than a few points, so a drag that starts on
/// the view goes to a pan around it.
private struct StillTap: UIGestureRecognizerRepresentable {
    let action: () -> Void

    func makeUIGestureRecognizer(context _: Context) -> UITapGestureRecognizer {
        UITapGestureRecognizer()
    }

    func handleUIGestureRecognizerAction(_ tap: UITapGestureRecognizer, context _: Context) {
        if tap.state == .ended {
            action()
        }
    }
}
#endif

#Preview {
    @Previewable @State var openRow: Int? = 0
    RowLabel(title: "Goblet squat", detail: "Kettlebell")
        .railRow()
        .swipeToDelete(id: 0, openRow: $openRow) { }
        .padding()
        .background(Color.pp(.background))
}
