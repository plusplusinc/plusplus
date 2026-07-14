import SwiftUI

/// A transient confirmation pill that auto-dismisses. Drive it with an optional
/// `String` binding: set it to show a message, and it clears itself after a
/// beat. Styled to the app grammar (Theme surface, `.standard` motion, no
/// chrome) and non-interactive, so it never eats a tap underneath it.
struct ToastModifier: ViewModifier {
    @Binding var message: String?
    var seconds: Double = 2.2

    @State private var hideTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    Text(message)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.border))
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                        .padding(.top, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        // A confirmation must never block the content beneath it
                        // (hidden layers stay hit-testable otherwise).
                        .allowsHitTesting(false)
                }
            }
            .animation(Theme.Anim.standard, value: message)
            .onChange(of: message) { _, newValue in
                hideTask?.cancel()
                guard newValue != nil else { return }
                hideTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(seconds))
                    guard !Task.isCancelled else { return }
                    message = nil
                }
            }
    }
}

extension View {
    /// Show a transient confirmation pill; the binding self-clears after a beat.
    func toast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}
