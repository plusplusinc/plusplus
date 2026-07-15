import Foundation
import SwiftUI
import Observation

/// What the user is looking at on the main surface, as one compact
/// line ("routines/Push Day") — injected into each Operator turn and
/// feeding the suggestion chips. Screens report via the
/// `.operatorContext(_:)` modifier (the `revealRoot(tab:atRoot:)`
/// reporting precedent): appear-only semantics, so a pop restores the
/// parent's line when the parent re-appears.
@Observable @MainActor
final class ViewContext {
    /// The active tab's raw value ("today", "routines", …).
    var tab: String = "today"
    /// The deepest reported screen line; nil means the tab root.
    var detail: String?

    /// The one line Operator sees.
    var line: String {
        detail ?? tab
    }
}

private struct OperatorContextReporter: ViewModifier {
    let line: String?
    @Environment(ViewContext.self) private var context

    func body(content: Content) -> some View {
        content.onAppear {
            context.detail = line
        }
    }
}

extension View {
    /// Report this screen as the visible context while it's frontmost.
    /// Pass nil from tab roots (clears a popped detail's line).
    func operatorContext(_ line: String?) -> some View {
        modifier(OperatorContextReporter(line: line))
    }
}
