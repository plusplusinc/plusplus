# PlusPlus

An iOS workout tracker. Swift 6, SwiftUI, SwiftData + CloudKit, iOS 26 minimum.

**There are no features yet.** The foundation is built and verified; the app renders a
placeholder. Do not add features, screens, or domain types without being asked — the data model
is meant to follow the first feature, not precede it.

## Architecture

Most code will live in local Swift packages under `Packages/`. The Xcode project is a thin shell.

```
App ──> Features ──> DesignSystem
              └────> WorkoutStore ──> WorkoutCore

DesignSystem  ──> SwiftUI only
WorkoutCore   ──> Foundation only
```

**These arrows are the rule, not a description.** Specifically:

- `WorkoutCore` imports nothing but Foundation. No SwiftData, no SwiftUI. That constraint is what
  lets its tests run in milliseconds without a simulator — do not trade it for convenience.
- `DesignSystem` never imports domain code. Components take strings and numbers; mapping a domain
  value into a component's inputs is the feature layer's job.
- Features never import each other. If two need the same thing, it belongs one layer down.
- Nothing imports `App`.

`WorkoutCore` and `Features` are currently empty placeholders. The packages exist because the
layering is the decision; the contents are not.

## Working in this project

**Never hand-edit `project.pbxproj`.** It is ~41 lines and should stay that way. `App/` is a
file-system-synchronized group, so a new file on disk is automatically in the target. Build
settings belong in `Config/*.xcconfig`, never in Xcode's Build Settings tab.

`Config/Info.plist` holds only keys with no `INFOPLIST_KEY_*` equivalent — currently just
`UIBackgroundModes`. Xcode merges it with the generated plist; both are needed.

Prefer adding a dependency to the relevant package's `Package.swift` over adding it to the Xcode
project, so the pbxproj stays untouched.

## Commands

```sh
# Fast tests. No simulator. Seconds.
swift test --package-path Packages/WorkoutStore

# Snapshot tests. Needs a simulator.
cd Packages/DesignSystem && \
  xcodebuild test -scheme DesignSystem -destination 'platform=iOS Simulator,name=iPhone 17'

# Build the app
xcodebuild build -project PlusPlus.xcodeproj -scheme PlusPlus \
  -destination 'platform=iOS Simulator,name=iPhone 17'

# Formatting. swift-format ships inside Xcode; there is nothing to install.
swift format --in-place --recursive App Packages
swift format lint --strict --recursive App Packages
```

Prefer XcodeBuildMCP tools over raw `xcodebuild` when available — structured errors, simulator
control, UI automation.

## Swift 6 concurrency

Swift 6 language mode with `complete` strict concurrency is on everywhere, packages included.

- `@unchecked Sendable` needs a comment justifying why it is safe. Last resort.
- `ModelContext` is not `Sendable`. Reach SwiftData through a `@ModelActor` and pass value types
  across the boundary — never a `ModelContext` or a `@Model` object.
- View models are `@MainActor @Observable`. Prefer `@Observable` over `ObservableObject`.
- `any` is required on existentials (`ExistentialAny` is enabled).

## Persistence

`WorkoutStoreContainer` owns *where and how* data is stored, not *what*. It takes a `Schema` as a
parameter so the data model can evolve without touching the storage wiring. The app does not
create a container yet.

`StorageMode` is explicit (`.shared` / `.local` / `.inMemory`) because the modes point at
different database files, and a silent relocation would look like data loss.

When a data model does arrive, CloudKit constrains the schema, and violations fail at runtime,
not compile time:

- Every property must be optional or have a default value.
- No `@Attribute(.unique)`.
- Relationships must be optional and have an inverse.

Prefer storing enums as raw strings with computed accessors so adding a case stays additive, and
decode unknown values to a fallback rather than throwing — a row synced from a newer app version
should degrade, not crash.

## Design system

No raw colours, spacing values, font sizes, or corner radii at call sites. Use the tokens in
`Packages/DesignSystem/Sources/DesignSystem/Tokens+*.swift`. If a token is missing, add one rather
than inlining a literal.

- Colours are semantic (`ppPositive`, not `ppGreen`) and live in `Tokens.xcassets`.
- Any number that changes in place — weight, reps, a timer — uses `.ppMetric` or `.ppMetricSmall`,
  which are monospaced. Proportional digits visibly jitter as they increment.
- Primary actions use `TouchTarget.primary` (60pt), not the 44pt minimum. This app gets used
  mid-set, one-handed.

Components should get snapshot coverage in light, dark, and accessibility-XXXL. There are no
components yet; `TokenSnapshotTests` covers the palette and is the template to copy.

## Testing

Swift Testing (`@Test`, `#expect`, `#require`), not XCTest.

Put a test in the cheapest tier that can hold it:

| Tier | Location | Cost |
| --- | --- | --- |
| Pure logic | `WorkoutCoreTests` (not yet created) | ~1ms, no simulator |
| Storage | `WorkoutStoreTests`, in-memory container | ~15ms, no simulator |
| Feature behaviour | `FeaturesTests` (not yet created), fake repository | ~1ms, no simulator |
| Rendering | `DesignSystemTests` | simulator required |

Never reach for a simulator-bound test when a pure one would do. Add the package to the CI matrix
in `.github/workflows/ci.yml` when you create its test target.

Snapshots compare perceptually (`perceptualPrecision: 0.98`) so cross-machine text rasterisation
does not cause false failures. Always give snapshotted views an explicit width —
`.sizeThatFits` proposes zero width and `Text` truncates to nothing, producing a silently wrong
reference image. Re-record by deleting the file in `__Snapshots__/` and re-running.

## Gotchas

- **Deleting the app does not reset data.** The store lives in the App Group container, which
  survives uninstall. Erase the simulator, or delete the container under
  `~/Library/Developer/CoreSimulator/Devices/<udid>/data/Containers/Shared/AppGroup/`.
- `.shared` storage mode succeeds on the simulator even without provisioning, because the
  simulator does not enforce App Group or iCloud entitlements. A working simulator is not
  evidence that entitlements are set up.
- `plutil -extract` rewrites the file in place. Use `plutil -p` to inspect, or pass `-o -`.

## Not yet built

Watch app, widgets and Live Activity, and HealthKit are planned and entitled but have no targets.
The App Group and CloudKit container are configured already because they determine where the
database file lives, which is expensive to change once real data exists.

Live Watch-to-phone session sync is unsolved. CloudKit is slow and unreliable off-wifi, which is
the normal state of a phone in a gym; WatchConnectivity for live state plus CloudKit for history
is the likely answer.
