---
paths: ["Packages/Sources/WorkoutStore/**", "Packages/Sources/WorkoutCore/**"]
---

# Persistence: SwiftData + CloudKit

`WorkoutStoreContainer` owns where and how data is stored, not what. It takes a `Schema`, so the
model list evolves without touching storage wiring. `StorageMode` is explicit (`.shared`,
`.local`, `.inMemory`) because the modes point at different database files.

CloudKit constrains the schema, and violations fail at runtime, not compile time:

- Every property is optional or has a default value.
- No `@Attribute(.unique)` and no `#Unique`.
- Relationships are optional and declare an inverse.
- Store enums as raw strings with computed accessors, and decode unknown values to a fallback.
  A row synced from a newer app version should degrade, not crash.
- No custom `CKShare` sharing through SwiftData; if sharing is ever needed it is a separate design.

Aggregates (weekly volume, best set, PR history) are computed in Swift over fetched rows. There is
no SQL pushdown. Keep the fetch narrow with a `FetchDescriptor` predicate and `propertiesToFetch`,
then reduce. If a screen needs a rollup repeatedly, persist a summary row updated on write rather
than recomputing from history on every appearance.

Schema changes are migrations. Add a `VersionedSchema` and a `SchemaMigrationPlan` stage for any
change that is not purely additive, and test the migration against a fixture store.

The Watch will keep its own local store. Live session state moves over `WatchConnectivity`;
CloudKit is the backstop for history, not the live channel.
