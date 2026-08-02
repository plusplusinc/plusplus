---
paths:
  - "PlusPlus/**"
  - "PlusPlusWatch/**"
  - "PlusPlusWidgets/**"
  - "PlusPlusShared/**"
---

# App surface map

⚠️ **This file describes the app as it IS. It is not a changelog** — reasoning
and round-by-round history live in docs/DECISIONS.md under dated entries.
Correct a claim here when the app changes; don't append a dated paragraph
beside it. The laws that constrain these surfaces live in the sibling rules:
**`design-grammar.md`** (color · keys · tags · motion · copy laws) and
**`navigation.md`** (tab bar, search surface, scope control, landings) and
**`today-rail.md`** (Today's band, rail, landmarks and pull) —
both load when you touch view code; read them before changing what they govern.

**Four tabs** on the native iOS 26 Liquid Glass `TabView` (`RootTabView`):
**Today · Routines · Exercises · Kit**. The three catalog tabs all render the
same `CatalogScopeView` — a tab picks which CATALOG, never which screen.
**Search is a floating key pinned above the tab bar** on those three
(`CatalogSearchDock`), morphing in place into a field; one query and one open
state, root-owned and shared by all three, so the tab bar stays the only scope
control. The container laws that constrain all of it (where the dock mounts and
why, the retired search tab and its six scope-control placements) are in
`navigation.md`; read them before changing anything in it.

**Today** — the unified timeline: scheduled work, carried-over work, and
committed sessions on a DATE-FIRST rail (each entry's date on its own row,
node centered on it, card below, never a date row with nothing under it),
with quick start as the rail's ANYTIME entry (dashed-shell `AnytimeCard`
below the future and above today; its wrapping keys morph in place into
config panels). The week's FACTS
(tally · block bar) pin as the surface's ONE section header, above the whole
timeline including the week ahead — nothing else on Today may pin (laws in
`today-rail.md`). A sync that WAS working and has broken adds one amber
advisory entry directly under the anytime card, sharing that row's gate so it
can never take the landing slot; it presents the GitHub tray directly.
Pull-to-refresh answers in the gap the pull opens (mechanics in
`today-rail.md`).

**Routines / Exercises / Kit** — catalog surfaces over `CatalogScopeView`,
MINE then CATALOG, a single-select facet row per scope (exercises kind/
muscle/movement/mechanic/sides · kit type · routines focus/effort/style),
PINNED as the list's one section header on tabs and as a top inset on
presented/picker surfaces (laws in `navigation.md`), with the swipe law
LEADING is curation / TRAILING is destructive. Each carries the floating search
key above the tab bar, which hides on a pushed detail. Routine detail keeps the
superset rail.

**The drawer** — the top-left ++ key (and a leading-edge drag on any tab
root) slides the whole app right, revealing `RevealSurface`: settings folded
inline (appearance, units, GitHub / Health / calendar sync, the active kit
as the hero card), Operator, and tiles opening trays (data, what's new,
about). Mechanics in `ui-interaction.md`.

**First run** — `WelcomeView` fuses splash and welcome into one continuous
shot; there is no onboarding flow — a fresh install's Today shows three
setup steps as timeline entries, gated bottom-up (`SetupState`).

**The session record** — a committed session opens `SessionDetailView`
(`Views/SessionDetailView.swift`; the standalone History screen died with #109 —
Today's timeline is the record).

**Platform surfaces** — a Live Activity spanning the workout (Dynamic Island +
Lock Screen), `.working` (exercise · set N/M · elapsed) swapping to `.resting`
(countdown + the same Skip / −15s / +15s row the phone shows), driven from
`ActiveSessionView`'s lifecycle by `WorkoutActivityController`. *Due today* and
*Streak* widgets read a `WidgetSnapshot` written to the App Group
(`group.com.davidcole.plusplus`) on launch/backgrounding; App Intents:
StartRoutine / DueToday read that same snapshot; OpenToday just opens the
app. ⚠️ There are NO
phone rest/timer local notifications — the rest cue is watch haptics plus the
island (#322 removed them, and the permission prompt with them).

**Watch** — WatchConnectivity companion: plan pushed on launch/backgrounding,
wrist execution (frozen step list, log/rest/haptics, early exit), finished
sessions syncing back as append-only history.

⚠️ **A session that misses Finish/Discard is salvaged on Today's next
appearance** (crash, or any dismissal the exit dialog never saw) rather than
becoming an invisible orphan. Anything that ends a session must keep this
true. Two riders (#510/#503): a session whose mirror ops are still arriving
from the wrist is NOT an orphan and is exempt (`LiveMirror.isLiveElsewhere`);
a salvaged finish anchors to `lastActivityAt`, never to relaunch time, and
emits the lifecycle op so the wrist journal closes too.
