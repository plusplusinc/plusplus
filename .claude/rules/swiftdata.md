---
paths:
  - "PlusPlus/**/*.swift"
  - "PlusPlusTests/**"
---

# SwiftData patterns (hard-won — violations have shipped bugs)

**Pre-insert relationship loss:** ⚠️ assigning a relationship on a model BEFORE `context.insert(model)` — including via an init parameter — when the targets are already inserted loses the assignment **nondeterministically**. This was the seeder's Bench-Press-as-bodyweight loss: #186's unreproducible field bug AND a night of ~50% CI red chased through three wrong theories (shared in-memory stores, cross-container aliasing, fixture-name collisions) before the fixture-precondition assert pinned it. Rule: **insert first, assign relationships after.** `Exercise.init(equipment:)` is only safe for containerless graphs (the SeedData definition tests). A repo-wide audit of remaining pre-insert assignments is #195.

**Every relationship declares its inverse:** the pre-insert tripwire kept firing until `Exercise.equipment` gained an explicit inverse (`Equipment.exercises`) — unidirectional to-manys are where CoreData integrity is documented to fray.

**Order management:** SwiftData relationships are unordered. Every ordered collection uses an `order: Int` property with `sortedX` computed properties and `reindexX()` methods called after every mutation. Sorted properties filter `isDeleted` objects.

**Sessions snapshot, never reference-only:** `WorkoutSession`/`SetLog` copy names/targets at start time; the `routine`/`exercise` references are conveniences that may go stale. History must survive template edits and deletions.

**`#Predicate` macro:** requires `import Foundation` in addition to `import SwiftData`.

**Enum case named `none` + Optional switches:** ⚠️ a `case none` on an enum used as `Optional<T>` makes `case .none:` inside a `switch` over the optional resolve to `Optional.none`, silently orphaning `.some(.none)`. Name such cases something else (`bodyweightOnly`, not `none`).

**Item-keyed presentation / `persistentModelID`:** the ID CHANGES at the first save of a fresh model — a temporary→permanent swap. ANY presentation keyed on it re-keys when a later autosave fires WHILE it is open, so the sheet DISMISSES and re-presents (or the pushed screen re-resolves) — a "flicker for no apparent reason". This covers `fullScreenCover(item:)`, `.sheet(item:)`, an item enum whose `id` is a model's `persistentModelID`, `.navigationDestination(item:)`, AND value-based `path.append(model)` (a `@Model`'s `Hashable` derives from `persistentModelID`). Save synchronously right after inserting, at the interactive call site (NOT inside the shared structure-mutation methods — those run in import/seed loops), so the model is permanent before it can back a presentation. Precedents: `WorkoutSession.start`, and `RoutineDetailView.addExercise`/`duplicateExercise` (the routine exercise-detail tray + superset picker, tray-flicker fix).
