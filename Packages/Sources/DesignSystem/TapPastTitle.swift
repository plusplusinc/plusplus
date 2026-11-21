import SwiftUI
#if os(iOS)
import UIKit
#endif

/// What a tap on a screen's own space does while an `EditableTitle` may be in edit: what it
/// does with the keyboard down, and the keyboard goes down with it.
///
/// The touch comes down before the edit ends (`onTouchDownOutsideTitle`), and by the tap's end
/// the edit has already ended either way, so where it came down is kept for the tap. A tap that
/// acts while the keyboard is still on its way down waits for it to be all the way down, so
/// what it opens and the keyboard never cross; a place that only acts at rest, as the room
/// below a list's last row, has only ended the edit. The caller reports the keyboard's coming
/// and going (`onKeyboardDown(for:perform:)`).
public struct TapPastTitle {
    /// Where the touch down last came.
    public enum Start {
        case onTitle
        /// Outside the title, with no edit to end.
        case outside
        /// Outside the title, ending its edit.
        case endingEdit
    }

    private(set) var start = Start.onTitle
    /// Whether the keyboard is up, from the start of its way up to the end of its way down.
    private(set) var isKeyboardUp = false
    /// Whether a tap's action waits for the keyboard to be down.
    private(set) var isWaiting = false

    public init() { }

    /// A touch came down. It drops an action an earlier tap left waiting: the new touch does
    /// its own thing.
    public mutating func touchDown(_ start: Start) {
        self.start = start
        isWaiting = false
    }

    /// The tap ended on a place that acts at rest, and, if `actsAfterEdit`, also after ending
    /// an edit. Returns whether it acts now; one that waits acts at `keyboardDidHide()`.
    public mutating func tap(actsAfterEdit: Bool) -> Bool {
        switch start {
        case .onTitle:
            return false
        case .endingEdit where !actsAfterEdit:
            return false
        case .outside, .endingEdit:
            isWaiting = isKeyboardUp
            return !isKeyboardUp
        }
    }

    public mutating func keyboardWillShow() {
        isKeyboardUp = true
    }

    /// The keyboard is all the way down. Returns whether a waiting tap acts now.
    public mutating func keyboardDidHide() -> Bool {
        isKeyboardUp = false
        defer { isWaiting = false }
        return isWaiting
    }
}

extension View {
    /// Tells `tap` of the keyboard's coming and going, and runs `action` for a tap that waited
    /// for it to be down: at the end of its way down, so what the tap opens rises only after.
    public func onKeyboardDown(
        for tap: Binding<TapPastTitle>,
        perform action: @escaping () -> Void,
    ) -> some View {
        #if os(iOS)
        onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillShowNotification,
        )) { _ in
            tap.wrappedValue.keyboardWillShow()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardDidHideNotification,
        )) { _ in
            if tap.wrappedValue.keyboardDidHide() {
                action()
            }
        }
        #else
        self
        #endif
    }
}
