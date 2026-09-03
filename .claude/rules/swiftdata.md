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

SwiftData has no SQL aggregate pushdown; rollups are computed in Swift over fetched rows.
