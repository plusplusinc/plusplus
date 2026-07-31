import SwiftUI

/// A tap-to-dismiss layer for a form's empty space, and the reasoning that
/// says where it goes.
///
/// A SwiftUI form has no keyboard dismissal unless it asks for one. Two
/// mechanisms, in order of how much work they do:
///
/// 1. **`.scrollDismissesKeyboard(.immediately)` on the scroll** — the
///    load-bearing one, and non-negotiable on any scrolling surface holding a
///    field. A plain `ScrollView` does NOT dismiss on scroll by default.
///    ⚠️ It is an ENVIRONMENT value, so it reaches every scrollable thing in
///    the subtree — including a `TextField(axis: .vertical)` that scrolls
///    inside itself once it outgrows its `lineLimit`. Give those
///    `.scrollDismissesKeyboard(.never)` (innermost wins), or dragging inside
///    the field to reach a later line drops the keyboard mid-edit.
/// 2. **`.keyboardGround(clearing:)`** — this. Tapping the form's empty space
///    puts the keyboard away, which is what a user means by "click out of it".
///
/// ⚠️ **It is a layer BEHIND the content, never an `.onTapGesture` on the
/// content stack.** Both reach the same taps in the good case — an ancestor's
/// tap gesture yields to whichever control the touch actually lands on, so
/// buttons and chips keep working either way — but they fail differently, and
/// only one failure is survivable. An ancestor gesture RACES the text field
/// for the tap that focuses it; lose that race and the keyboard blinks shut
/// on the way IN, which is worse than having no dismissal at all. Behind, it
/// can only ever receive a touch nothing in front of it took, so no
/// regression is possible.
///
/// ⚠️ **The price of sitting behind is a THIN catchment**, and it is thinner
/// than "the gaps": section labels, captions, each field's own filled chrome
/// (padding ring included) and any card background all take the tap first.
/// What is left is the side margins, the bands between sections, and any
/// header that carries no control. So this is always the SECOND exit — never
/// ship it as the only one.
///
/// ⚠️ **It only covers what it is attached to.** A header that is a SIBLING
/// of the scroll needs its own copy; the scroll's exits do not reach it, and
/// a blank header directly above a focused field is the most obvious empty
/// place there is. `ExerciseEditorView` gives its `SheetHeader` one for
/// exactly this reason. ⚠️ The `pushedScreenChrome` band is the KNOWN
/// exception and does not have one: it arrives as a `safeAreaInset` from a
/// component every pushed screen shares, so grounding it means either
/// changing all of them or giving that component an opt-in hook. Deliberate,
/// deferred, and the reason a pushed form's header does not answer a tap.
///
/// Taps are not pans, so nothing here claims the scroll — `ui-interaction.md`'s
/// claim-vs-does law is about drags.
extension View {
    /// Puts a tap-to-clear layer behind this view. Pass the form's
    /// `@FocusState` projection: `.keyboardGround(clearing: $focusedField)`.
    ///
    /// ⚠️ The focus state must be OPTIONAL-valued (`Field?`), which is the
    /// shape a multi-field form wants anyway. A `@FocusState var focused:
    /// Bool` (`SearchFieldBody`'s shape) does not bind here and fails with
    /// "generic parameter 'Value' could not be inferred", which points at
    /// the wrong thing — add a `Bool` overload rather than hand-rolling the
    /// layer again.
    func keyboardGround<Value: Hashable>(clearing focus: FocusState<Value?>.Binding) -> some View {
        background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { focus.wrappedValue = nil }
        )
    }
}
