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

`RoutineStore` is the one `@ModelActor`, opened through
`WorkoutStoreContainer.make(mode:schema:migrationPlan:)` with its own schema, versioned: every
stored shape shipped so far is a `VersionedSchema` (`RoutineSchemaV1` to `V6`, the older ones in
`RoutineSchema+Shipped.swift`), and `RoutineMigrationPlan` runs a lightweight stage between each,
since each change only added an attribute or a model. Staged migration refuses a store whose
shape matches none of the plan's versions, so a shipped version never changes: a stored change
is a new version, a new stage, and a test that opens the last shape, written on disk, under it
(`RoutineStoreUpgradeTests`). Its models, `StoredRoutine`, `StoredRoutineExercise`, `StoredWorkout`, and `StoredSet`, are
internal:
`Routine`, a value, crosses the boundary, and the store diffs its rows by id rather than
replacing them, so a row's identity, and later its sync record, is stable. A row carries its
`position`, since a relationship is unordered, and its plan: `sets`, `reps` or `seconds` (apart,
so a stored number never changes meaning if an exercise's measure does), and `weight` with
`weightUnit`, the unit's raw string. Each is optional, and nil means never stored: a row saved
before plans existed reads as its exercise's default, field by field, as does a value out of
range or for the other measure; a weight never stored, or in an unknown unit, reads as the
exercise's starting weight in the region's unit, which `launch(weightUnit:)` is given. A
saved weight keeps its own unit. Every save stores every
row's plan, default or not, setting only the fields that changed, so an unchanged row stays
clean. A row's `supersetID`, optional, joins it to the rows next to it with the same id; a
routine is normalized as it loads (`normalizeSupersets()`): a split run gets a second id, a run
of one goes plain, and a superset's rows take its first row's sets, so a routine saved before
supersets opens with every row plain. The store calls `save()` itself, since an
actor's context does not autosave. An empty routine is deleted rather than stored, and every save
marks the routine edited (`editedAt`), since a routine saves only when its name or rows changed.
Opening a saved routine (`openRoutine`) marks it opened (`openedAt`), apart, so an open is never
taken for an edit; a store written before `openedAt` reads it as `distantPast`. A routine's
recency is the later of the two: `routinesByRecency` sorts on it in Swift, since a sort
descriptor can't take the later of two dates, a tie going by id, and launch opens the routine
that list puts first.

A workout (`Workout`, stored as `StoredWorkout`) holds its routine's id, not a relationship, and
the routine's name as it was, so renaming or deleting the routine leaves it. It has no status:
its start, the moment it was paused, the seconds paused before, and its end make it running,
paused, or finished, and its time is worked out from them at any moment, so a relaunch or a
lock never loses any. Its sets (`LoggedSet`, stored as `StoredSet`, a cascade relationship) each
keep their row's id and exercise slug, round, side (`Side`'s raw string, unknown reading as
nil), and numbers as done beside the numbers planned, each measure and weight apart as a row's
are, with a `position` for the order logged; `save(_ workout:)` diffs them by id, as a routine's
rows. Discard deletes it, its sets with it. `launch(weightUnit:)` opens a workout in progress with
its routine (an empty one under its id and name if the routine is gone; of two in progress, as
sync could leave, the one started later), else the routine last opened or edited, unless a
workout finished after that, which opens a new routine. While a workout runs, a routine cleared
to nothing is kept (`keepsEmpty`), and deleted once the workout ends.

SwiftData has no SQL aggregate pushdown; rollups are computed in Swift over fetched rows.
