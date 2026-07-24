import SwiftUI
import PlusPlusKit

/// The "Swap for…" tray (2026-07-24): suggested replacements for an
/// exercise, ranked by similarity, instead of a push into the whole
/// catalog. One exercise's substitutes read the same at planning time
/// (routine detail) and mid-workout (the session overview), so this is
/// the shared surface both present.
///
/// Deliberately dumb about what a pick MEANS: it emits the chosen
/// `Exercise` and lets the caller decide (a planning swap resets targets
/// to defaults; a session swap commits a default-config block). The full
/// catalog — with search, filters, create-new, and the session's
/// configure-before-add — is one tap further, behind "Browse all
/// exercises", which each caller wires to its own escape.
struct ExerciseSwapTray: View {
    @Environment(\.dismiss) private var dismiss

    /// The exercise being replaced — names the tray and is the similarity
    /// origin (its row is excluded from `suggestions` by the caller).
    let origin: Exercise
    /// Same-muscle substitutes, kit-doable-first then similarity-ranked
    /// (`ExerciseFilterState.swapSuggestions`).
    let suggestions: [Exercise]
    /// Active-kit gear names, for each row's "needs X" availability flag.
    let available: Set<String>
    /// A replacement was chosen.
    let onPick: (Exercise) -> Void
    /// The full catalog was requested (nothing here fit).
    let onBrowseAll: () -> Void

    /// Keep the tray a curated shortlist, not a second catalog: the top
    /// slice by rank, with everything else reachable through Browse all.
    /// Kit-doable moves sort first, so a trim only ever drops the
    /// least-similar not-in-kit options.
    private static let visibleLimit = 8

    private var shown: [Exercise] { Array(suggestions.prefix(Self.visibleLimit)) }
    private var hasMore: Bool { suggestions.count > shown.count }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Swap for…", actionLabel: "Cancel", closeOnly: true) {
                dismiss()
            }
            .padding(.horizontal, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(intro)
                        .font(.system(.footnote))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)

                    if shown.isEmpty {
                        Text("No similar moves in the catalog yet.")
                            .font(.system(.subheadline))
                            .foregroundStyle(Theme.textFaint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(shown) { exercise in
                                Button {
                                    onPick(exercise)
                                } label: {
                                    ExerciseRowContent(
                                        exercise: exercise,
                                        available: available,
                                        showsChevron: false,
                                        leadingSymbol: exercise.modalitySymbolName
                                    )
                                    .padding(.horizontal, 4)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("swapSuggestion")
                                .overlay(alignment: .bottom) { Divider().overlay(Theme.border) }
                            }
                        }
                        .padding(.top, 10)
                    }

                    // The catalog is always one tap further — the tray is a
                    // shortlist, never a dead end. A QUIET key, not a green
                    // CreateRow: browsing navigates, it doesn't create. Says
                    // "more" when the shortlist was trimmed.
                    QuietKey(
                        label: hasMore ? "Browse all exercises" : "Browse the full catalog",
                        systemImage: "square.grid.2x2",
                        identifier: "swapBrowseAllButton"
                    ) {
                        onBrowseAll()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 14)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 20)
            }
        }
        .presentationBackground(Theme.surface)
        .presentationDetents([.medium, .large])
    }

    private var intro: String {
        "Similar \(origin.muscleGroup.displayName.lowercased()) moves. The ones in your kit come first; the rest show what they need."
    }
}
