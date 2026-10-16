---
paths: ["Packages/Sources/WorkoutStore/**"]
---

# Persistence: SwiftData

`WorkoutStoreContainer` owns where and how data is stored, not what. It takes a `Schema`, so the
model list evolves without touching storage wiring. `StorageMode` is explicit (`.local`,
`.inMemory`) because the modes point at different databases.

The store will sync through CloudKit, and CloudKit constrains the schema at runtime, not compile
time. Every `@Model` follows these from the start:

- Every property is optional or has a default value.
- No `@Attribute(.unique)` and no `#Unique`.
- Relationships are optional and declare an inverse.
- Store enums as raw strings with computed accessors, and decode unknown values to a fallback,
  so a row written by a newer app version degrades instead of crashing.

`RoutineStore` is the one `@ModelActor`, opened through `WorkoutStoreContainer.make(mode:schema:)`
with its own schema. Its models, `StoredRoutine` and `StoredRoutineExercise`, are internal:
`Routine`, a value, crosses the boundary, and the store diffs its rows by id rather than
replacing them, so a row's identity, and later its sync record, is stable. A row carries its
`position`, since a relationship is unordered, and its plan: `sets`, `reps` or `seconds` (apart,
so a stored number never changes meaning if an exercise's measure does), and `weight` with
`weightUnit`, the unit's raw string. Each is optional, and nil means never stored: a row saved
before plans existed reads as its exercise's default, field by field, as does a value out of
range or for the other measure; a weight never stored, or in an unknown unit, reads as the
exercise's starting weight in the region's unit, which `launchRoutine(weightUnit:)` is given. A
saved weight keeps its own unit. Every save stores every
row's plan, default or not, setting only the fields that changed, so an unchanged row stays
clean. The store calls `save()` itself, since an
actor's context does not autosave. An empty routine is deleted rather than stored, and every save
marks the routine edited, since a routine saves only when its name or rows changed.

SwiftData has no SQL aggregate pushdown; rollups are computed in Swift over fetched rows.
