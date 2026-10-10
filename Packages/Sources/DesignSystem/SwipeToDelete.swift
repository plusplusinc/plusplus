import SwiftUI

/// Where a row swiped left comes to rest when the finger lifts, as in Mail: dragged past half
/// its width, or flung left, it is deleted; dragged past half the Delete key, it opens to show
/// the key; otherwise it closes. A fling right closes it. Offsets are how far the swipe has
/// gone, negative to the left.
enum SwipeSettle: Equatable {
    case closed
    case open
    case delete

    /// A fling, in points per second: faster than a deliberate drag.
    static let flingSpeed: CGFloat = 1000

    static func settle(
        offset: CGFloat,
        velocity: CGFloat,
        width: CGFloat,
        keyWidth: CGFloat,
    ) -> Self {
        let distance = -offset
        if velocity >= flingSpeed {
            return .closed
        }
        // A flick can begin and end within a couple of touch samples, and a pan's translation
        // starts from where it began, so a fling counts however short it reports.
        if distance > width / 2 || velocity <= -flingSpeed {
            return .delete
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
    /// `isOpen` is a binding so a list can keep one row open at a time.
    public func swipeToDelete(isOpen: Binding<Bool>, onDelete: @escaping () -> Void) -> some View {
        modifier(SwipeToDelete(isOpen: isOpen, onDelete: onDelete))
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

    private var offset: CGFloat {
        dragOffset ?? (isOpen ? -keyWidth : 0)
    }

    private var pastDelete: Bool {
        -offset > width / 2
    }

    func body(content: Content) -> some View {
        content
            .accessibilityAction(named: "Delete", onDelete)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                if isOpen {
                    withAnimation { isOpen = false }
                }
            }
            .overlay(alignment: .trailing) { deleteKey }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
            #if os(iOS)
            .gesture(
                HorizontalPan(
                    isOpen: isOpen,
                    onChange: { translation in
                        let start = isOpen ? -keyWidth : 0
                        dragOffset = min(0, start + translation)
                    },
                    onEnd: { translation, velocity in
                        let start = isOpen ? -keyWidth : 0
                        settle(offset: min(0, start + translation), velocity: velocity)
                    },
                ),
            )
            #endif
            .sensoryFeedback(.impact, trigger: pastDelete) { _, isPast in isPast }
            .hotReloadable()
    }

    @ViewBuilder private var deleteKey: some View {
        if offset < 0 {
            let shape = RoundedRectangle(cornerRadius: Radius.key)
            Button(role: .destructive, action: delete) {
                // At its natural size, from the key's leading edge, so it slides in with the
                // key rather than shrinking to fit.
                Text("Delete")
                    .font(.ppButton)
                    .foregroundStyle(.pp(.textPrimary))
                    .fixedSize()
                    .padding(.leading, Spacing.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            // The key's leading edge follows the finger.
            .frame(width: -offset)
            .background(.pp(.destructive), in: shape)
            .clipShape(shape)
            .padding(.vertical, Spacing.xs)
            .accessibilityHidden(!isOpen)
        }
    }

    private func settle(offset: CGFloat, velocity: CGFloat) {
        let rest = SwipeSettle.settle(
            offset: offset,
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

    func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_: UIPanGestureRecognizer, context: Context) {
        context.coordinator.isOpen = isOpen
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context _: Context) {
        let translation = pan.translation(in: pan.view).x
        switch pan.state {
        case .began, .changed:
            onChange(translation)
        case .ended:
            onEnd(translation, pan.velocity(in: pan.view).x)
        case .cancelled, .failed:
            onEnd(0, 0)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isOpen = false

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) && (isOpen || velocity.x < 0)
        }
    }
}
#endif

#Preview {
    @Previewable @State var isOpen = true
    RowLabel(title: "Goblet squat", detail: "Kettlebell")
        .padding(.vertical, Spacing.sm)
        .swipeToDelete(isOpen: $isOpen) { }
        .padding()
        .background(Color.pp(.background))
}
