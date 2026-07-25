import SwiftUI
import SwiftData
import PlusPlusKit

/// Choosing an exercise — for a routine you're building, or mid-workout.
///
/// It is a SHEET showing the Exercises catalog exactly as its tab shows it
/// (Dave, 2026-07-25): `CatalogScopeView` in picker mode, so MINE then CATALOG,
/// the collapsible "require more equipment" group, the favorite and delete
/// swipes, and the create-at-the-top row are all the same ones — with the
/// search field at the BOTTOM of the sheet. Routine building used to PUSH a
/// separate picker with its own filter bar; there is one exercise list in the
/// app now, and this is it wearing a different job.
///
/// This view is just the shell around that: which callback a pick runs, and the
/// configure sheet the session path stacks on top.
struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss

    /// The sheet's title — "Add exercise" building a routine, "Swap exercise"
    /// replacing one.
    var title = "Add exercise"
    /// The configured-selection path (session adds): a row tap opens a
    /// configure sheet — set count + targets — stacked on the picker, and Add
    /// hands back the finished `SessionExerciseConfig`. When set, it takes
    /// precedence over `onSelect`.
    var onConfigured: ((SessionExerciseConfig) -> Void)?
    /// The plain path (routine building): a row tap selects immediately; the
    /// routine's own detail sheet does the configuring.
    var onSelect: ((Exercise) -> Void)?

    /// The configure sheet's working config (configured path only) — held so
    /// the sheet's edits survive to Add.
    @State private var pendingConfig: SessionExerciseConfig?

    var body: some View {
        CatalogScopeView(picking: .exercises, title: title) { exercise in
            if onConfigured != nil {
                // Stack the configure sheet ON the picker — no
                // dismiss-then-present handoff (the documented
                // presentation-drop class).
                pendingConfig = SessionExerciseConfig(exercise: exercise)
            } else {
                onSelect?(exercise)
                dismiss()
            }
        }
        // Configure-before-add (session picks): the sheet stacks on the picker;
        // Add commits the config and dismisses the picker (iOS tears the
        // stacked sheet down with its parent).
        .sheet(item: $pendingConfig) { config in
            ExerciseConfigSheet(config: config) {
                onConfigured?(config)
                dismiss()
            }
        }
    }
}
