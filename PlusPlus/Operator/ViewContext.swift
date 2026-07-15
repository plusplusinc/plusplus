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
        content
            .onAppear {
                context.detail = line
            }
            // A pop must clear the line: the tab-level wrappers never
            // disappear on a push, so their onAppear can't re-fire on
            // the way back — the DETAIL clears itself instead, guarded
            // so a sibling that already took over isn't stomped.
            .onDisappear {
                if context.detail == line {
                    context.detail = nil
                }
            }
    }
}

extension View {
    /// Report this screen as the visible context while it's frontmost.
    /// Attach to pushed detail screens; the line clears itself on pop.
    func operatorContext(_ line: String?) -> some View {
        modifier(OperatorContextReporter(line: line))
    }
}
