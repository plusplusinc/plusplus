---
paths:
  - "PlusPlus/Views/**"
  - "PlusPlusWatch/**"
---

# Interaction & navigation laws (each one shipped a bug before it was a law)

**SwipeRevealRow content contract:** row content must carry NO tap affordance (no Button, no onTapGesture) — activation is the component's `onTap`, composed exclusively with the reveal drag (once the drag activates at 16 pt, the tap is structurally impossible). Companion ordering law (#276): the contentShape + gesture attach INSIDE `.offset` — attached outside, the hit region keeps the unshifted frame and covers the revealed actions. Full mechanism: docs/DECISIONS.md 2026-07-09 swipe entries. Native `.swipeActions` outside List arrives in iOS 27; the migration retiring the component is #277.

**Value navigation destinations register at stack roots, never on pushed screens** (#262). And **a pushed screen that appends to the path must itself be a path entry** (#291): value appends BENEATH a live `isPresented:`/item destination replace it and break back-pop; boolean destinations ON TOP of value pushes are fine. `path.append` is not idempotent — root-only affordances guard on `path.isEmpty`; template-row pushes carry a one-shot flag reset in `onAppear`.

**Routine-family presentation/navigation keys on the model's `uuid`, never `persistentModelID`** (2026-07-14, the tray-flicker decoupling): `persistentModelID` swaps temporary→permanent at a fresh model's first save and re-keys an open sheet/push (the flicker). Push/present a small value type carrying the `uuid` (`ModelRefs.swift`: `RoutineRef`, `IdentifiedUUID`) and resolve the model in the destination via `ModelContext.routine(uuid:)` (a FETCH, so a just-created routine resolves with no `@Query` lag). `Routine`/`ExerciseGroup`/`RoutineExercise` `uuid` is `UUID?` (optional for a lightweight migration) but effectively always non-nil (init default + launch backfill), so `.map`/`if let` at the few call sites. Internal animation/list identity (the zoom-transition pairing, `ForEach` in browse lists, swipe-open state) MAY stay on `persistentModelID` — it's not a presentation that flickers, and the door-saves already make it safe.

**Screens that commit edits on exit must also commit in `onDisappear`** — the full-width swipe-back pops entirely in UIKit, so SwiftUI `onBack` closures never run. Idempotent, guarded against the deleted-model race.

**Long-press row gestures use `.simultaneousGesture`** — `.gesture(LongPressGesture().sequenced(DragGesture()))` starves the ScrollView pan (#99). The rail's gestures live on a UIKit `UILongPressGestureRecognizer` attached to the enclosing UIScrollView for exactly this reason; `scrollDisabled` only during an active drag.

**`opacity(0)` does NOT remove a view from hit testing** — hidden layers need `allowsHitTesting(false)`.

**One-shot deferred UI beats re-check preconditions at fire time** (StartFlashButton's deferred fire, the lingering +1 finish): cancel on disappear, check `isDeleted`/session state before acting.

**Shared controls live in `Views/Components/`** once they appear in a second view — never redefined across screens.
