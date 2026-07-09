import SwiftUI
import TipKit

/// TipKit is reserved for exactly one concept: introducing supersets
/// (the 2026-07-09 audit's call — everything else the UI now says in
/// place, or nowhere). Tips render with the system's own appearance —
/// they're scaffolding, not brand surface — and the creation tip is
/// invalidated the moment the user builds a superset unprompted.

/// Routine detail, when the rail already shows a loop the user may not
/// have drawn themselves (an instantiated template, a shared import):
/// what the glyph means.
struct SupersetLoopTip: Tip {
    var title: Text { Text("The loop is a superset") }
    var message: Text? { Text("One round runs each exercise once, alternating.") }
    var image: Image? { Image(systemName: "square.fill.on.square.fill") }
}

/// Routine detail, when there's material to pair (≥2 exercises) but no
/// superset yet: how to make one. Structurally exclusive with the loop
/// tip — see SupersetTipAnchor in RoutineDetailView.
struct SupersetCreationTip: Tip {
    var title: Text { Text("Pair exercises into a superset") }
    var message: Text? { Text("Open an exercise and choose Superset with… — or hold its rail dot and drag over a neighbor.") }
    var image: Image? { Image(systemName: "square.fill.on.square.fill") }
}
