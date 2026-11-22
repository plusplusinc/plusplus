import SwiftUI

extension View {
    /// A row's one swipe action, in the system's look: swiped left, the row shows `title` in red,
    /// and a tap on it runs `action` with `value`. Inside a `swipeActionsContainer()`.
    ///
    /// `swipeActions` written in place builds its actions on every run of the body holding them,
    /// and each build reaches the container as a preference: a screen whose body ran twice in the
    /// frame its rows were first laid out logged "Bound preference
    /// SwipeActionsValuesPreferenceKey tried to update multiple times per frame" for each row.
    /// Here the actions are built again only when `title` or `value` changes.
    ///
    /// So `action` is the one from the last build, not the latest: it should act only on `value`
    /// and on state it reaches through storage (`@State`, an observed object), never on a `let`
    /// or an `@Environment` value of the view that made it, which may be an earlier copy's.
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

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title && lhs.value == rhs.value
    }

    func body(content: Content) -> some View {
        content.swipeActions(edge: .trailing) {
            Button(title, role: .destructive) { action(value) }
        }
    }
}
