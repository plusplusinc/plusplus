# PlusPlus

A workout tracker for incrementing yourself. iOS 26+, Swift 6, SwiftUI, SwiftData + CloudKit.

## Getting started

```sh
open PlusPlus.xcodeproj
```

No generation step, no bootstrap script. The project is committed and `App/` is a
file-system-synchronized group, so files on disk are automatically in the target.

Run the fast tests without ever launching a simulator:

```sh
swift test --package-path Packages/WorkoutStore
```

## Layout

| Path | What lives there |
| --- | --- |
| `App/` | Entry point, entitlements. Deliberately thin. |
| `Packages/WorkoutCore` | Domain types and pure logic. Foundation only. Currently empty. |
| `Packages/WorkoutStore` | Storage wiring: App Group container, CloudKit, storage modes. |
| `Packages/DesignSystem` | Design tokens. SwiftUI only, no domain knowledge. |
| `Packages/Features` | Screens and view models. Currently empty. |
| `Config/*.xcconfig` | Every build setting. Nothing lives in the pbxproj. |

The dependency rules between these are enforced by convention and documented in
[CLAUDE.md](CLAUDE.md) — read that before adding an import.

## Status

Foundation only. The app builds, runs, and renders a placeholder — there are no features, no
data model, and no persisted data yet, by design. What exists is the scaffolding: project and
build configuration, module layering, design tokens, storage wiring, test harness, and CI.

Not built yet: Watch app, widgets and Live Activity, HealthKit. The App Group and CloudKit
container are already configured because they determine where the database file lives, which is
expensive to change once real data exists.

Shipping to TestFlight is wired up but needs Apple credentials — see
[docs/testflight.md](docs/testflight.md).
