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

`Store` is the one `@ModelActor`, opened through
`WorkoutStoreContainer.make(mode:schema:migrationPlan:)` with its own schema, versioned: every
stored shape shipped so far is a `VersionedSchema` (`RoutineSchemaV1` to `V14`, the older ones in
`RoutineSchema+Shipped.swift`), and `StoreMigrationPlan` runs a lightweight stage between each,
since each change only added an attribute or a model. Staged migration refuses a store whose
shape matches none of the plan's versions, so a shipped version never changes: a stored change
is a new version, a new stage, and a test that opens the last shape, written on disk, under it
(`StoreUpgradeTests`). Its `Stored…` models are internal, with older names: `Workout`, a value
stored as `StoredRoutine`, crosses the boundary, and the store diffs its rows by id rather
than replacing them, so a row's identity, and later its sync record, is stable. A row carries its
`position`, since a relationship is unordered, and its plan: `sets`, `reps` or `seconds` (apart,
so a stored number never changes meaning if an exercise's measure does), and `weight` with
`weightUnit`, the unit's raw string. Each is optional, and nil means never stored: a row saved
before plans existed reads as its exercise's default, field by field, as does a value out of
range or for the other measure; a weight never stored, or in an unknown unit, reads as the
exercise's starting weight in the region's unit, which `launch(weightUnit:)` is given. A
saved weight keeps its own unit. Since V7 a row also carries its rest: `rest`, the seconds the
user last set, nil if never, and `isRestAuto`, true while rest follows the reps or time, which
keeps `rest` for when Auto goes off; and its superset's `roundRest` and `isRoundRestAuto`, the
same on every member, nil and true on a plain row. A rest out of range reads as never set,
and one set by hand with no seconds in range as Auto, never set; a store from before V7 opens
with every rest automatic. Every save stores every row's plan, default or not, setting only
the fields that changed, so an unchanged row stays clean. A row's `supersetID`, optional,
joins it to the rows next to it with the same id; a workout is normalized as it loads
(`normalizeSupersets()`). The store calls `save()` itself, since an actor's context does not
autosave. An empty workout is deleted rather than stored, and every save marks the workout
edited (`editedAt`), since a workout saves only when its name or rows changed. Opening a saved
workout (`openWorkout`) marks it opened (`openedAt`), so an open is never taken for an edit. A
workout's recency is the later of the two: `workoutsByRecency` sorts on it in Swift, a tie
going by id, and launch opens that list's first.

`LoggedWorkout`, stored as `StoredWorkout`, holds its workout's id, not a relationship, and
the workout's name as it was, so renaming or deleting the workout leaves it. It has no status:
its start, the moment it was paused, the seconds paused before, and its end make it running,
paused, or finished, and its time follows from them, so a relaunch loses none. Since V14 it
keeps each pause's times (`pauseTimes`), its Health type from Finish, and Health's id. Its sets (`LoggedSet`, stored as `StoredSet`, a cascade relationship) each
keep their row's id, exercise id and, since V9, name, round, side (`Side`'s raw string, unknown reading as
nil), and numbers as done beside the numbers planned, each measure and weight apart as a row's
are, with a `position` for the order logged, (V11) its rest's start and change, (V12) the
seconds +15 s added (`timeAdded`), and (V13) its rest's skip (`restSkippedAt`); `save(_ loggedWorkout:)` diffs them by id, as a workout's rows.
Since V12 it keeps the count under way (`SetCount`).
Discard and Log's Delete delete it, its sets with it. `launch(weightUnit:)` opens a logged
workout in progress with its workout (an empty one under its id and name if the workout is gone; of two in progress, the
one started later), else the workout last opened or edited, unless one
finished after that, which opens the Workouts list.

A row's `exerciseID` resolves through `ExerciseList`, the customized built-ins (V10) and V8's `StoredExercise`s; a row
it can't resolve is left out at load and kept by saves. `deleteExercise` removes its rows too.
