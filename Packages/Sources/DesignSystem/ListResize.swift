import SwiftUI

extension View {
    /// Marks the update that changes `count` as one that resizes this list's rows: from that
    /// update until the animation it runs on has really ended, the rows inside read
    /// `isListResizing`, so a superset's loop heads ease to their new places (`Rail`) and the
    /// room under the list's end holds (`roomBelow(_:)`). Change `count` inside the
    /// `withAnimation` that resizes the rows, on the same animation.
    ///
    /// Read from the animated count itself, not an animation's completion: SwiftUI sometimes runs
    /// a completion before the first frame, while the rows go on resizing for the whole motion.
    public func listResizes(_ count: Int) -> some View {
        modifier(ListResize(shown: Double(count), target: Double(count)))
    }
}

extension EnvironmentValues {
    /// Whether the rows of the list this view is in are resizing on an animation
    /// (`listResizes(_:)`).
    @Entry var isListResizing = false
}

/// The count as drawn, which the animation runs from the old value to the new one, against the
/// count it is going to: they differ from the update that changes it until the animation is over,
/// the first update included, which draws the old value.
private struct ListResize: ViewModifier, Animatable {
    var shown: Double
    let target: Double

    var animatableData: Double {
        get { shown }
        set { shown = newValue }
    }

    func body(content: Content) -> some View {
        content.environment(\.isListResizing, shown != target)
    }
}
