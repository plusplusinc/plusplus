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
    /// What the main surface is showing, as one of the frozen catalog keys
    /// or "today" — "today", "routines", "exercises", "equipment".
    ///
    /// ⚠️ These are NOT the surface names. Since the tab bar came out
    /// (2026-08-04) there are two surfaces, Today and Search, and the search
    /// surface writes its SCOPE here via `FindScope.contextKey` rather than
    /// the word "search". Deliberate: this line is what Operator reads and
    /// what `OperatorChips` is unit-tested against, and "the user is looking
    /// at routines" is the useful fact — "the user is looking at search"
    /// would be a regression in what the assistant knows. The surface name
    /// lives on `RevealController.activeTab`, which answers a different
    /// question (which root's swipe gate applies).
    var tab: String = "today"
    /// The deepest reported screen line; nil means the surface root.
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
