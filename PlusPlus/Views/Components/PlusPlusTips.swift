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
/// superset yet: how to make one. One describable path only (the HIG
/// call from #270, taken all the way in build 45: cramming the drag
/// gesture in as a second clause read clunky — the ring gesture stays
/// a discovered mechanic, and using it retires this tip anyway).
/// Structurally exclusive with the loop tip — see SupersetTipInline
/// in RoutineDetailView.
struct SupersetCreationTip: Tip {
    var title: Text { Text("Pair exercises into a superset") }
    var message: Text? { Text("Tap an exercise and choose Superset with the one above or below.") }
    var image: Image? { Image(systemName: "repeat") }
    var options: [any TipOption] { [Tips.MaxDisplayCount(1)] }
}
