---
paths:
  - "PlusPlusTests/**"
  - "PlusPlusUITests/**"
  - "PlusPlusKit/Tests/**"
  - "PlusPlusCLI/Tests/**"
---

# Testing patterns

**Bug fixes start with the failing test:** write a test that reproduces the bug and watch it fail BEFORE touching the fix — in Kit/CLI run it locally (`swift test`), for app targets add it to the suite CI runs. A fix without a red-first test has no proof it fixed anything, and the regression has no tripwire.

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

**⚠️ `isHittable` is NOT "visible", and that cost seven dispatched rounds** (2026-07-30, #483). XCUITest does not model the app's own floating chrome as covering anything, so an element sitting under the navigation bar or the tab bar reports `isHittable == true` and the tap lands on the BAR. Same for an element that is realized but off-screen — existence is not visibility, and a coordinate tap at an off-screen frame lands on nothing at all. Today's committed card was found under each bar in turn, and a swipe-open row's cell frame turned out to be at `x = -92` (the open row slides left, so its leading fifth is off the display and a `dx: 0.15` tap landed at `x = -29`). **Before tapping anything on a scrolling surface, put its frame inside a band clear of BOTH bars** — scroll toward whichever band it is in, since the fold is not always the problem — and prefer an absolute `app.coordinate(...).withOffset(...)` tap, which dispatches through hit testing, over an element tap, which goes through accessibility and was swallowed every time here.

**⚠️ Put GEOMETRY in the assertion message, not another guess.** A remote session can never reach the `ui-screenshots` artifact (blob storage, blocked at CONNECT), but the ui-test job publishes assertion text as `::error::` annotations, which the API does serve — ~400 characters of it. Three rounds read `DELETE hittable=true · navigated=false · onList=true` as "the row ignores taps"; printing `rect(frame)` ended it in one. `rect(_:)`, `buttonInventory()` and `textInventory()` exist for this.

**Popping a pushed screen goes through `tapBack`, never `app.buttons["backButton"]`.** The app has TWO back controls: `pushedScreenChrome`'s custom key, and the system bar's own on screens that wear a system title (routine detail, since #470). A helper that knows one of them breaks the moment a screen changes chrome, which is exactly what happened.

**XCUITest cannot see hit-area or gesture-layer bugs** — its taps dispatch via accessibility and bypass gesture overlays. Any gesture-layer change needs a device pass before it's called fixed, regardless of a green suite.

**`#expect` with `allSatisfy`:** extract to a local first: `let allMatch = items.allSatisfy(\.prop); #expect(allMatch)`. Direct inline call causes macro expansion issues.

**The app supports `--uitest-reset`** (in-memory store, flourishes/tips/notifications disabled) for clean smoke-test launches; `--uitest-welcome` opts the welcome-flow test in.

**CI flakes (moved from CLAUDE.md, 2026-08-01):** ui-test has two known flavors — `app.launch()` wedging on a runner simulator, and exit-65 runs where the identical tree passes on re-run. Re-run once before suspecting code. (The swipe test's synthesized-drag flake, #273/#274, was fixed 2026-07-15: `testSwipeRevealActionSurvivesRelease` reveals through `revealDelete`, which waits for hittability and re-drags to absorb runner jitter.) All four jobs surface failing-test names as `::error::` annotations readable via the check-runs API. ⚠️ Job LOGS are API-reachable (2026-07-30): `mcp__github__get_job_logs` with `return_content: true` — only the ARTIFACTS are out of reach from a sandbox.

**⚠️ `swiftc -parse` on a Linux session proves SYNTAX ONLY, and reading it as more is how a red CI happens** (2026-08-01, #509 b15). It has no SDK, so it cannot type-check: a missing `try` on a throwing initializer, a wrong argument label, an actor-isolation violation and a `Sendable` breach all pass it and then fail the app `test` job. Two habits follow. Parse-check anyway — it catches real typos in seconds and costs nothing. But never report a change as verified on the strength of it, and when a diff turns on TYPE-level facts (throwing inits, isolation, Sendable conformance), state in the PR that CI is the first real compile. The `swift test` runs in `PlusPlusKit/` and `PlusPlusCLI/` ARE full compiles — that asymmetry is the trap, since the same command in a Kit directory means much more than it does against an app file.

**Remote validation layer:** 10 XCUITest smoke flows (`ui-test` job: dispatch + main pushes) upload a `ui-screenshots` artifact reviewable from a browser — the onboarding timeline, welcome flow, template-detail open, swipe-release regression contracts, the mascot form-demo sheet, and the early-finish-through-recap door (#503).
