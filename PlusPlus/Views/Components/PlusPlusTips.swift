import SwiftUI
import TipKit

/// One-time education (v4 §G): the ambient captions died; what survives
/// as TIPS is shown once with the system's own appearance — tips are
/// scaffolding, not brand surface — and invalidated the moment the user
/// does the thing unprompted.

/// Catalog browse: what membership toggles do (replaces the deleted
/// "Toggles curate your library…" caption).
struct CatalogCurationTip: Tip {
    var title: Text { Text("Toggles curate your library") }
    var message: Text? { Text("Removing never touches routines or logged history.") }
}

/// Library lists: the swipe affordance (replaces the deleted list
/// footers).
struct SwipeActionsTip: Tip {
    var title: Text { Text("Swipe left for actions") }
    var message: Text? { Text("Remove from your library anytime — the catalog keeps everything.") }
}

/// Schedule editor: the Pace anchor concept (replaces the ambient
/// caption; a real concept, not decoration).
struct PaceAnchorTip: Tip {
    var title: Text { Text("Pace is anchored to you") }
    var message: Text? { Text("3×/7d counts from your last completion, not the calendar week — miss a day and nothing stacks up.") }
}
