import SwiftUI

extension View {
    /// A row's one swipe action, in the system's look: swiped left, the row shows `title` in red,
    /// and a tap on it runs `action` with `value`. Inside a `swipeActionsContainer()`.
    ///
    /// `swipeActions` written in place builds its actions on every run of the body holding them,
    /// and each build reaches the container as a preference: rows built three times in one frame
    /// log "Bound preference SwipeActionsValuesPreferenceKey tried to update multiple times per
    /// frame" for each row, as an add or a drop did with them. Here SwiftUI usually compares them
    /// with the last and builds them again only when `title` or `value` changed; not always, so
    /// what keeps a row's first layout from logging it is that nothing in that frame runs its
    /// body a third time (`Rail`'s node measures, the workout screen's title).
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

/// `rowSwipe(_:value:action:)`'s actions, equal while what they show and act on is. When the body
/// around it runs again, SwiftUI may compare an `Equatable` modifier with the last and skip its
/// body when equal; on some first layouts it ran the body with no compare.
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
