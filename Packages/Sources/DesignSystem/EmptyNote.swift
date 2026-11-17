import SwiftUI

/// One quiet line where a screen's content would be while it has none, as "No exercises" on an
/// empty routine: centered in the room it is given, in the to-do gray, wrapping at large text
/// sizes. It takes no touches, so a tap through it lands on what is under it, and it stays put
/// as the keyboard rises.
public struct EmptyNote: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.ppButton)
            .foregroundStyle(.pp(.toDo))
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .ignoresSafeArea(.keyboard)
    }
}

extension View {
    /// While `isEmpty`, `text` as an `EmptyNote` over the view. The line fades in and out with
    /// the change that empties or fills it.
    public func emptyNote(_ text: String, isEmpty: Bool) -> some View {
        overlay {
            if isEmpty {
                EmptyNote(text)
                    .transition(.opacity)
            }
        }
    }
}

#Preview {
    EmptyNote("No exercises")
        .background(Color.pp(.background))
}
