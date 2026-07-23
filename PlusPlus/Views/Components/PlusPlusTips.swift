import SwiftUI
import TipKit

/// TipKit is reserved for exactly one concept: introducing supersets
/// (the 2026-07-09 audit's call — everything else the UI now says in
/// place, or nowhere). Tips render with the system's own appearance —
/// they're scaffolding, not brand surface. Education is one-shot
/// (`MaxDisplayCount(1)`): shown once, never re-presented over the
/// rail. Building a superset by hand — the sheet's "Superset with…",
/// the ring gesture, or picking into an existing group — invalidates
/// BOTH tips; a ring eject (the same dot-drag mechanic) invalidates
/// the creation tip.

/// Routine detail, when the rail already shows a loop the user didn't
/// draw themselves (an instantiated template, a shared import): what
/// the glyph means.
struct SupersetLoopTip: Tip {
    var title: Text { Text("The loop is a superset") }
    var message: Text? { Text("Its exercises alternate. Each round runs them all once.") }
    var image: Image? { Image(systemName: "repeat") }
    var options: [any TipOption] { [Tips.MaxDisplayCount(1)] }
}

/// Routine detail, when there's material to pair (≥2 exercises) but no
/// superset yet: a POPOVER pinned to the first exercise row, teaching
/// the GESTURE plus what a superset is (Dave, 2026-07-23 — reversing
/// build-45's sheet-path-only copy: the drag is the app's most
/// expressive interaction and deserved to be taught, and anchoring to
/// a real row fixes what made the build-45 balloon read as floating).
/// Display is gated by the `canPair` parameter (set by RoutineDetailView
/// from live structure) so the popover attachment itself can stay
/// unconditional on the row — no #270 identity churn.
struct SupersetCreationTip: Tip {
    /// True while the open routine has ≥2 exercises and no superset yet.
    @Parameter static var canPair: Bool = false

    var title: Text { Text("Build a superset") }
    var message: Text? { Text("Two exercises, run back to back each round. Hold the dot beside one and drag to the other.") }
    var image: Image? { Image(systemName: "repeat") }
    var rules: [Rule] { [#Rule(Self.$canPair) { $0 == true }] }
    var options: [any TipOption] { [Tips.MaxDisplayCount(1)] }
}
