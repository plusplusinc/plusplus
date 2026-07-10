---
paths:
  - "PlusPlusTests/**"
  - "PlusPlusUITests/**"
  - "PlusPlusKit/Tests/**"
  - "PlusPlusCLI/Tests/**"
---

# Testing patterns

**SwiftData test containers:** ⚠️ in-memory configurations (`isStoredInMemoryOnly: true`) share state across containers in one process — **even uniquely named ones** (proved twice on CI 2026-07-08; Swift Testing runs suites in parallel, so the corruption is scheduling-dependent ~50% flake). The only real isolation is a throwaway on-disk store per container:
```swift
let schema = Schema([Exercise.self, Equipment.self, Routine.self, ExerciseGroup.self, RoutineExercise.self])
let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("mytests-\(UUID().uuidString).store")
let config = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
let container = try ModelContainer(for: schema, configurations: [config])
let context = ModelContext(container)
```

**Fixture names:** use "Probe …" names instead of catalog names, so a corrupted seed can never masquerade as a fixture collision.

**Seed data access:** `SeedData.makeBuiltInExercisesForTesting(equipment:)` exposes internal exercise creation. Production code uses `SeedData.loadIfNeeded(context:)`.

**Lazy-List UI-test spot checks:** XCUITest only sees realized rows — List rows below the first screen don't exist to `waitForExistence`. Spot-check rows guaranteed on the FIRST screen, and pick items robust to data growth (the alphabetically-first names — #222's catalog growth pushed Battle Ropes under the fold and broke onboarding).

**XCUITest and accessibility modifiers:** ⚠️ `.accessibilityAddTraits` / `.accessibilityAction` on a multi-child container flatten it into ONE accessibility element — child `staticTexts` vanish from XCUITest queries. `.accessibilityElement(children: .combine)` has the same hiding effect. XCUITest sees through Button labels but NOT through modifier-flattened containers. VoiceOver work on such rows is #164's remit — don't bolt traits onto swipe-row content.

**XCUITest cannot see hit-area or gesture-layer bugs** — its taps dispatch via accessibility and bypass gesture overlays. Any gesture-layer change needs a device pass before it's called fixed, regardless of a green suite.

**`#expect` with `allSatisfy`:** extract to a local first: `let allMatch = items.allSatisfy(\.prop); #expect(allMatch)`. Direct inline call causes macro expansion issues.

**The app supports `--uitest-reset`** (in-memory store, flourishes/tips/notifications disabled) for clean smoke-test launches; `--uitest-welcome` opts the welcome-flow test in.
