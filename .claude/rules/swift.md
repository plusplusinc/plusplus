---
paths: ["**/*.swift"]
---

# Swift conventions

Swift 6 language mode, strict concurrency, approachable concurrency, and `ExistentialAny` are on
everywhere. The app, `DesignSystem`, and `Features` default to `@MainActor` isolation;
`WorkoutCore` and `WorkoutStore` are nonisolated by default.

- In main-actor-default modules, do not sprinkle `@MainActor` on types: it is already implied.
  Leave the main actor deliberately with `@concurrent` (for CPU work) or `nonisolated`.
- In nonisolated modules, make types `Sendable` value types or actors. If you are writing
  `nonisolated` more than once per file in a UI module, the code belongs one layer down.
- `@unchecked Sendable` needs a comment justifying why it is safe. Last resort.
- State is `@Observable`. Never `ObservableObject`, `@Published`, or `@StateObject` in new code.
- `ModelContext` is not `Sendable`. Reach SwiftData through a `@ModelActor` off the main actor
  and pass value types across the boundary, never a `ModelContext` or a `@Model` object.
- `any` is required on existentials. Prefer generics or concrete types over existentials.
- No force unwraps, force casts, or `try!` outside tests. SwiftLint treats them as errors.
- Errors are typed enums that conform to `LocalizedError` where a user could see them.
- Free functions and small structs for math and rules (e1RM, plate math, volume, timers).
  They test in milliseconds and run anywhere, including the Watch.
- Comments explain why, not what. A comment that restates the code is noise; delete it.
- US English in identifiers, comments, and strings.
