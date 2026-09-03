---
paths: ["**/*.swift"]
---

# Swift conventions

Swift 6 language mode, strict concurrency, approachable concurrency, and `ExistentialAny` are on
everywhere. The app and `DesignSystem` default to `@MainActor` isolation; `WorkoutStore` is
nonisolated by default.

- In main-actor-default modules, do not sprinkle `@MainActor` on types: it is already implied.
  Leave the main actor deliberately with `@concurrent` (for CPU work) or `nonisolated`.
- In nonisolated modules, make types `Sendable` value types or actors.
- `@unchecked Sendable` needs a comment justifying why it is safe. Last resort.
- State is `@Observable`. Never `ObservableObject`, `@Published`, or `@StateObject`.
- `ModelContext` is not `Sendable`. Reach SwiftData through a `@ModelActor` off the main actor
  and pass value types across the boundary, never a `ModelContext` or a `@Model` object.
- `any` is required on existentials. Prefer generics or concrete types over existentials.
- No force unwraps, force casts, or `try!` outside tests. SwiftLint treats them as errors.
- Comments explain why, not what. A comment that restates the code is noise; delete it.
- US English in identifiers, comments, and strings.
