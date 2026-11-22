import SwiftUI

extension View {
    /// A row's one swipe action, in the system's look: swiped left, the row shows `title` in red,
    /// and a tap on it runs `action` with `value`. Inside a `swipeActionsContainer()`, as the
    /// workout screen's and the Workouts screen's rows are.
    ///
    /// `swipeActions` written in place builds its actions again each time the view holding them
    /// runs its body, and each build reaches the container as a preference. A screen that changes
    /// its state in the frame its rows are first laid out runs its body twice in that frame, as
    /// the workout screen does when its rail takes its column's width and its nodes' insets, and
    /// both screens do when their titles first report whether they are under the bar; SwiftUI
    /// logged "Bound preference SwipeActionsValuesPreferenceKey tried to update multiple times
    /// per frame" for each row. Built here, the actions are built again only when `title` or
    /// `value` changes.
    ///
    /// `action` is kept from the last build, not compared: it should act on `value` and on state
    /// it reaches through storage, as a view's own methods reach its `@State`.
    public func rowSwipe<Value: Equatable>(
        _ title: LocalizedStringKey,
        value: Value,
        action: @escaping (Value) -> Void,
    ) -> some View {
        modifier(RowSwipe(title: title, value: value, action: action))
    }
}

/// `rowSwipe(_:value:action:)`'s actions, equal while what they show and act on is: SwiftUI runs
/// an `Equatable` modifier's body only when its value changes.
struct RowSwipe<Value: Equatable>: ViewModifier, Equatable {
    let title: LocalizedStringKey
    let value: Value
    let action: (Value) -> Void
    /// Told each time the actions are built, as the body runs; only the tests set it.
    var onBuild: (() -> Void)?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title && lhs.value == rhs.value
    }

    func body(content: Content) -> some View {
        onBuild?()
        return content.swipeActions(edge: .trailing) {
            Button(title, role: .destructive) { action(value) }
        }
    }
}
