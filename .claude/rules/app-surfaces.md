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
**`navigation.md`** (tab bar, search surface, scroll and landing mechanics) —
both load when you touch view code; read them before changing what they govern.

**Five tabs** on the native iOS 26 Liquid Glass `TabView` (`RootTabView`):
**Today · Routines · Exercises · Kit · Search**. The last wears
`Tab(role: .search)`, so the system separates it and gives it the bar→field
morph. The three catalog tabs and the search tab all render the same
`CatalogScopeView` — a tab picks which CATALOG, never which screen. The
container laws that constrain that row (the `.principal` toolbar row, search
scopes, the accessory's retirement, the morph's state-write rule) are in
`navigation.md`; read them before changing anything in it.

**Today** — the unified timeline: scheduled work, carried-over work, and
committed sessions, over a sticky week strip that lives INSIDE the scroll.
Pull-to-refresh answers in the gap the pull opens (mechanics in
`navigation.md`).

**Routines / Exercises / Kit** — catalog surfaces over `CatalogScopeView`,
MINE then CATALOG, a single-select facet row per scope (muscle/movement/
mechanic/sides · category · focus/effort/style — laws in `navigation.md`),
with the swipe law LEADING is curation / TRAILING is destructive. Routine
detail keeps the superset rail.

**Platform surfaces** — a Live Activity spanning the workout (Dynamic Island +
Lock Screen), `.working` (exercise · set N/M · elapsed) swapping to `.resting`
(countdown + the same Skip / −15s / +15s row the phone shows), driven from
`ActiveSessionView`'s lifecycle by `WorkoutActivityController`. *Due today* and
*Streak* widgets read a `WidgetSnapshot` written to the App Group
(`group.com.davidcole.plusplus`) on launch/backgrounding; App Intents
(StartRoutine / DueToday / OpenToday) read that same snapshot. ⚠️ There are NO
phone rest/timer local notifications — the rest cue is watch haptics plus the
island (#322 removed them, and the permission prompt with them).

**Watch** — WatchConnectivity companion: plan pushed on launch/backgrounding,
wrist execution (frozen step list, log/rest/haptics, early exit), finished
sessions syncing back as append-only history.

⚠️ **A session that misses Finish/Discard is salvaged on Today's next
appearance** (crash, or any dismissal the exit dialog never saw) rather than
becoming an invisible orphan. Anything that ends a session must keep this true.
