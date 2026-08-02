---
paths:
  - "PlusPlus/Views/**"
---

# Tab bar, search, and scroll architecture

Every ⚠️ here is a law learned on device — the build number names the failing
build. Don't re-try retired mechanisms; docs/DECISIONS.md and git history hold
the post-mortems. A law tagged **(recheck: iOS 27)** encodes an OS-26 bug:
re-test it on the next major SDK before assuming it still binds. Siblings: `today-rail.md` (Today's band, rail, landmarks, pull — split out
2026-08-02), `design-grammar.md` (color/key/tag/copy laws),
`app-surfaces.md` (what each screen is), `ui-interaction.md` (gesture laws).

## The tab bar

**The chrome is the SYSTEM'S, and the bar carries FOUR tabs** (2026-08-02 —
the hand-drawn `AppBottomBar` was DELETED 2026-07-26 after three device
rounds; scroll legibility, home-indicator clearance and label alignment are all
things a real tab bar does for free). `TabView` = **Today · Routines ·
Exercises · Kit**.

**The tab bar IS the scope control, searching or not.** The fifth
`Tab(role: .search)` is GONE and search is a native item in the TOP toolbar
(section below), which is what lets the tabs stay visible and usable mid-query. Everything the search tab needed — a hand-laid
`.principal` toolbar row, a title/spacing/margin exception set on one surface,
and a ban on state-writing geometry reads across the whole subtree — went with
it.

- ⚠️ **The tab bar does NOT minimize on scroll** (Dave, 2026-07-27):
  `.tabBarMinimizeBehavior(.onScrollDown)` is GONE — it existed only to move
  the retired bottom accessory between placements. The `.soft` bottom scroll
  edge effect handles content passing under a full-size bar.
- ⚠️ **The bottom scroll edge effect is `.soft` on every scrolling tab root**
  — `.hard` (139, a full-width slab) and hiding it outright (148, read-through)
  are both RETIRED. Soft shows only where content is actually under the chrome.
  It goes ON THE SCROLLING CONTENT, never as a background on the bar (build
  133's mistake).
- ⚠️ **Never hide tabs.** `Tab.hidden(_:)` works and preserves state, but the
  bar does NOT REFLOW around hidden tabs — build 139 hid the catalogs during
  search and got a full-width group capsule with Today rattling around alone in
  it (Dave's screenshot). Moot as a search behaviour now; still true.
- A native `Tab` item is not a view the app can decorate — per-scope counts
  can never ride tab labels (retired).
- **State-writing geometry reads are no longer banned in this subtree**
  (2026-08-02). The ban existed because `.onGeometryChange` / `GeometryReader`
  + `PreferenceKey` anywhere under the `TabView` broke `Tab(role: .search)`'s
  morph on FIRST activation (nav-diag 4e), and there is no search role left to
  break. Reading WITHOUT writing is still the cheaper habit and the two live
  reads (`RoutineDetailView`'s rail width, `OverflowCapsuleRow`) stay as they
  are; `UIFont` metrics still beat a probe where they answer.
- ⚠️ Because **a `Tab`'s content is its own view tree**, the three catalog
  tabs are three live INSTANCES, so every broadcast needs one named owner:
  `ownsLandings` (`tabKey == scope.tab.rawValue`) makes the catalog TAB the
  consumer of arrivals and Operator pushes. ⚠️ And because a tab's content is
  built on FIRST selection, a notification alone reaches nobody on a
  never-visited tab — every cross-tab landing rides a pending SLOT consumed on
  receive OR on appear (`RoutineArrival`, `OperatorArrival`); a bare post is
  the build-76 silent-dead-tap class. Each tab passes its scope as a LITERAL
  (shared state renders one frame of the outgoing catalog before any `onChange`
  catches up).
- ⚠️ **Scroll-position sync between catalog tabs is RETIRED** (tried in 139):
  `.scrollPosition(id:)` doesn't take on a `List` the way it does on
  `ScrollView` + `scrollTargetLayout()`.

## One view: CatalogScopeView

**Searching a catalog and browsing it are ONE view** (2026-07-25). Search adds
a QUERY, never a destination — `RootTabView` mounts the three
`CatalogScopeView`s, one per `FindScope`, and shows them on `tab` alone, keying
nothing on `searching`. It replaced `RoutineListView` /
`ExercisesTabView` / `EquipmentTabView` / `FindOrCreateView` AND the pushed
`EquipmentCatalogScreen`; the same view serves as a `.tab` (own stack, query
bound from the root because the field lives in the bar) and
`.presented(setupMode:)` (pushed chrome + its own header field + an item
destination, #291) — the second is what onboarding step 1, the drawer's "Edit
your kit", the picker's filter escape and the template gear-check open.

**The PRESENTED equipment catalog is one flat alphabetical run**, while the
Kit TAB groups MINE/CATALOG (2026-07-25). Deliberate: the presented form is
the ADD surface, and with tiers every quick-add lifts the row you just swiped
to the top and shifts the rows under your thumb — worst in onboarding step 1.
The in-kit checkmark carries membership there.

## The search surface: a native item in the TOP toolbar

**Search is a minimized magnifier in the trailing toolbar group of the three
catalog tabs, expanding in place into a field** (Dave, build 176: "search in
the top bar like this, which I like"). Today has no search — a timeline of
derived state has nothing to narrow.

⚠️ **The floating key ABOVE THE TAB BAR is RETIRED** (Dave, build 176: "we
moved away from the custom floating-above-the-tab-bar thing"). `CatalogSearchDock`,
its bottom `safeAreaInset` mount, its glass circle→capsule morph and every law
that served them are DELETED, not deprecated. Do not reintroduce a dock: the
whole reasoning chain behind it — rise with the keyboard, inset the last row,
hide on push — exists only for a control that lives at the BOTTOM of the
screen. A top-bar item has none of those problems, because a keyboard cannot
cover the navigation bar and a bar item is not in the scroll.

⚠️ **Three modifiers, in Apple's order** (`.searchable` first, then
`.searchToolbarBehavior`, per its own Discussion: "place this modifier after
the searchable modifier that renders search in the toolbar"). Each is
load-bearing:

- **`placement: .toolbar`, STATED and never inferred.** With no placement the
  call takes `.automatic`, which the system re-guesses on EVERY presentation:
  build 175 opened correctly, closed, then re-opened as a FULL-WIDTH field that
  pushed the ++ key and the kit switcher out of the bar (Dave: "as if the search
  icon button thinks it needs to take up the full width of the toolbar because
  there are no other toolbar items — though there are"). Naming the placement is
  what makes it JOIN the trailing group instead of claiming the row. ⚠️ It is a
  PREFERENCE, not a guarantee — Apple falls back to automatic when it cannot
  satisfy one — so if the full-width state returns, this is where it starts.
- **`.searchToolbarBehavior(.minimize)`** renders it as a magnifier rather than
  an expanded field at rest. ⚠️ `.minimize`, NOT `.minimized`: Apple's own
  Discussion sample writes a name that does not exist, and the declared type
  property wins over the prose.
- **`.searchPresentationToolbarBehavior(.avoidHidingContent)`** keeps the ++ key
  and the kit switcher in the bar while search is active. Without it the system
  clears the bar to make room — the build-143 emptying.

**One query, one open state, both owned by `RootTabView`** and shared by all
three catalogs. Typing on Routines and tapping Exercises KEEPS the query; a trip
to Today restores the open field on the way back (`isPresented` is bound, which
is what buys that). ⚠️ That does not break the "a stale invisible query reads as
data loss" law, it satisfies it: the query is only ever hidden on a tab it could
not have filtered, and it returns visible in an open field with its own clear
key. `land(on:)` must still CLOSE search, or the entrance flash plays inside a
filtered list.

- ⚠️ **The tab bar stays visible and usable while searching, and now genuinely
  so.** The dock's accepted cost — the keyboard covers the tab bar, so changing
  catalog mid-query meant dismissing it first — is GONE with the dock. The
  field is at the top; the tabs are never underneath it. `.scrollDismissesKeyboard(.immediately)`
  is still right on every catalog, but it is no longer the ONLY route back to
  the tabs, so it is no longer load-bearing in that specific sense.
- **The field, the Cancel and the clear glyph are the SYSTEM's.** ⚠️ That
  retires, for this surface only, the app's `xmark`-means-collapse and
  `delete.left`-means-clear laws — the system brings its own vocabulary and the
  scope-by-neighbour rule says a system field wears it. `SearchFieldBody` still
  serves the picker sheet, which is app-drawn chrome and keeps the r11 opaque
  anatomy and the mono-is-DATA law.
- **It does NOT auto-focus on tab arrival** — the magnifier is a control; the
  keyboard rises when you tap it.
- **Creation is the TOP list row, and the verb PREDICTS the tap**: **Create**
  (`New <object>` empty, `Create "<query>"` queried) COMMITS inline; **Add**
  OPENS something ("Add to routine…", the overview's "Add exercise"). All three
  catalogs create, so all three read alike — Kit's "Add … as equipment" was the
  one row that said Add and committed anyway, converged #507. Casing is
  `String.sentenceCasedFirst`. Empty results NEVER dead-end. The ONE thing that
  removes a create is an EXACT-name collision (2026-07-24): trimmed query
  case-insensitively equals an existing name → that type's create is suppressed
  (`FindOrCreateEngine.Collisions`), never a dead end since an exact match
  always ranks into results. Partial matches still offer create.
- `.listStyle(.plain)` PINS one header at a time; the catalog spends that pin
  on the FACET ROW (law below). A pinned header wears solid
  `Theme.background` — it occludes the rows beneath it.
- **Return does not navigate** (Dave, 2026-07-26): submitting puts the keyboard
  away, it does not choose a result — no `onSubmit` action on any field.

## Retired: the search tab and its scope control

Two years of placements in one paragraph, kept so nobody re-walks them. **A
segmented scope control existed only because search was its own TAB** and
needed to say which catalog it was narrowing; it settled after SEVEN builds in
six placements as a native `Picker` in a hand-built `.principal` toolbar row,
and it died with the tab on 2026-08-02. ⚠️ **None of these are to be re-tried**
(post-mortems: docs/DECISIONS.md + git). `tabViewBottomAccessory` does not rise
with the keyboard (137–139, 144) and kills app-authored animation (139).
Native `.searchScopes` renders exactly ONCE per app run on a bottom-morphed
field, and at the TOP (140–143, four activation routes). A `.bottomBar`
`ToolbarItem` lands in the SAME ROW a search-role field expands into (145).
A TOP `safeAreaInset` under the bar (147) was one row too many. A `.principal`
item is a TITLE VIEW that UIKit centres in the BAR, not between the side items,
so ANY side item makes the two gaps asymmetric by its own width and
`.frame(maxWidth: .infinity)` cannot fix it (150). All: recheck iOS 27.
⚠️ **Do NOT hand-roll a segmented control** if one is ever wanted again —
iOS 26's interactive glass belongs to tab bars and segmented controls alone.
The custom `SegmentedTabs` was RETIRED 2026-07-24; every other former segmented
site is a native `Picker` (`.segmented` for short unit/mode toggles, a pushed
`NavigationSelectRow` for multi-word modes).

## Scopes, tiers, and the missing-equipment group

- **Today is a TAB, never a scope**: a timeline of derived state has nothing
  to narrow. `All` is GONE; an **empty query shows the scope's WHOLE list,
  grouped as its tab groups it**.
- **All three scopes read alike: MINE then CATALOG, plus ONE facet row**
  (filtering returned 2026-07-31, reversing 2026-07-25) — the Kit tab means
  "equipment, mine first", not "my kit". The row per scope: exercises kind ·
  muscle · movement · mechanic · sides; kit type; routines focus · effort ·
  style. State in `CatalogFilterState` — ephemeral per `CatalogScopeView`
  INSTANCE, reset on scope change, applied in `FindOrCreateEngine` so facets
  narrow and the query ranks. ⚠️ **Multi-select facets are SETS and compose OR
  inside a facet, AND across them** (#498 — "chest or shoulders, and
  compound"); an EMPTY set means the facet is off, never "match nothing". Only
  the two binaries stay single-select optionals (see design-grammar for which
  control each takes).
  ⚠️ **What a facet hides is NAMED, and counted in the pass that built the
  list** (#507): `FindOrCreateEngine.outcome` scores each candidate first and
  classifies by facet second, so an excluded MATCH is counted where it was
  already examined. That one number feeds the "N hidden by filters · show"
  QuietKey above the create row (QUERIED lists only: the create row is the
  near-duplicate path, and with no query the summary chip already says it),
  the empty state naming the filters, and "N of M shown". Never derive it as
  "unfiltered total minus shown" — deferred behind the popover that pass was
  fine, in the render path it is one per keystroke, the cost the per-scope
  counts were retired over. Empty results add a
  "Clear filters" QuietKey; the create row never filters; an item that can't
  answer an active facet drops out under it (customs under the attribute
  chips) — muscle excepted, customs carry their own groups. ⚠️ Except where it
  can't answer AT ALL: a hand-built routine has no Effort or Style (both
  resolve through `catalogTemplate`), so under those two it groups as **"not
  rated"** — the missing-equipment shape and law, narrowed never vanished, one
  `.unrated` section after both tiers (#507); it still clears every facet it
  CAN answer. ⚠️ **On tab roots
  the row is the SECTION HEADER of the ONE section holding the whole list**
  (2026-08-01). Both other mounts are RETIRED — a top `safeAreaInset` (#521)
  and first-list-content (the chips scrolled away) — for the reason the Today
  band law states in full (`today-rail.md`: a pinned top inset costs the
  system large title, on a `List` and a `ScrollView` alike). PRESENTED and PICKER keep the pinned, opaque top
  `safeAreaInset` (app-drawn chrome); no geometry probes anywhere.
  ⚠️ **`listSectionSpacing(.custom(0))` + `contentMargins(.top, 0)` are GONE**
  (2026-08-02). That pair seated the row from rest on the SEARCH surface, where
  a `.plain` List's scrolling top padding left it 22 pt low and blinked the nav
  bar's scrolled-under hairline for exactly that window. All three catalogs
  wear the system LARGE title now and it travels through that space, so
  closing it would seat the chips against the bar and re-open the #521
  argument. ⚠️ If that hairline is ever chased again, seating the row is the
  fix, never a top `scrollEdgeEffectStyle`. Typing
  still reaches everything without chips: muscle groups, movement patterns
  and hidden synonyms (`CatalogSearchSynonyms` — "erg", "rdl", "trx") ride
  `ExerciseFilterState.searchHaystack` and the equipment scorer.
- **Kit availability is NOT a filter** (2026-07-25): nothing is HIDDEN by the
  active kit. What the kit can't do groups under a collapsible **"N
  exercises/routines require more equipment"** disclosure
  (`MissingEquipmentHeaderRow`, `Views/Components/`), AFTER the doable items,
  COLLAPSED BY DEFAULT (whole-row toggle + chevron; `Theme.Anim.standard`).
  The header is a plain scrolling row (not pinned) in NEUTRAL ink — amber
  stays the per-row advisory; an amber header reads as an alarm over a group.
  Header copy describes the ITEMS, not the user (the no-obligation law); the
  one sentence lives in `MissingEquipmentPhrasing`. Same pattern on all three
  surfaces that used to filter (on Routines `.onMove` sits on the doable group
  only). In `FindOrCreateEngine` the split is a pure `.missing(noun:)`
  `Section.Kind`, per-tier (`MISSING_MINE`/`MISSING_CATALOG`): MINE/CATALOG is
  the primary division, kit availability the secondary. All scope: capped
  doable overview then a missing group per type — which still shows when a
  type has ONLY missing results, so an only-missing query never empties.
  Collapse state is ephemeral per-surface `@State`, reset on entry; a
  cross-tab arrival that needs gear expands the group so its entrance flash
  isn't on a hidden row.
- **A tab root with nothing narrowing it leads with FRONT MATTER, and the
  whole list still follows** (2026-08-02): no query and no facet on a
  catalog TAB renders `CatalogFrontPage` above the sections — one statement
  of what the scope and the kit come to, then the scope's axes as
  `SelectableChip` runs (exercises muscle · movement; kit type; routines
  focus). ⚠️ It PREPENDS, never replaces: the empty-query law above is
  intact, which is what keeps routines' `.onMove` reachable (reorder is
  empty-query-only, so a replacement would have no home for it), leaves the
  missing-equipment disclosure alone, and keeps the facet row's pinned-header
  seat. A chip WRITES a facet, so the block is self-dismissing — it is the
  facet row spelled out, for the arrival where a chevron chip opening a tray
  of unfamiliar words is no help. ⚠️ The search-TAB exclusion this law
  shipped with is MOOT as of the floating key (2026-08-02): there is no
  search tab to exclude, and "no query and no facet" already says it — a
  query is what makes a catalog a query surface now, whichever tab it is
  on. The reasoning it carried still binds: do not give the facet row a
  competing top block. Counts come from a
  DEDICATED `FindOrCreateEngine.outcome` pass at empty query held in `@State`
  and rebuilt on a key (scope · kit MEMBERSHIP · catalog sizes), never
  derived in `listBody` — a per-render count is the cost per-scope counts
  were retired over. Chips state the axis value's CATALOG total, not its
  kit-doable subset: a doable count reads "Carry · 0" on a kit with no
  loadable gear, and the statement already carries the kit frame.
- ⚠️ The next law is about CATALOG LIST rows, not detail screens. A pushed
  detail has always been a cross-reference graph (exercise → equipment →
  routine, `CatalogDetailViews`), and since 2026-08-02 exercise detail's
  **NEAR THIS** section links exercise → exercise, self-recursively through
  the same item destination. That is adjacency browsing on a detail screen,
  not a scope switch in a list.
- **Cross-scope discovery is the TAB BAR** — never link rows, and per-scope
  result counts are GONE (2026-07-25: the central `matchCounts` costs a second
  ranking pass per keystroke, and a `Tab` item is not a view the app can paint
  a number on anyway). Prompts and empty states use `FindScope.searchNoun`,
  not `label`.

## Tab roots and scroll

A **tab root** wears the SYSTEM navigation bar — `.navigationTitle` +
`.navigationBarTitleDisplayMode(.large)`, the ++ key (`AppMenuKey`) as a
leading `ToolbarItem` and the root's own accessory (the catalogs' kit
switcher) as a trailing one — Today carries NONE: every start lives on the
rail (the anytime card's sport keys + Train) or on a routine's own card.
⚠️ **Both keys are NATIVE toolbar controls** (Dave, 2026-08-02): bare labels
that take the toolbar's own plating, sizing and press feedback.
`.sharedBackgroundVisibility(.hidden)` came off with the raised caps — it
existed only to stop an app-drawn cap nesting inside the toolbar's shared glass
(a box in a box), and a bare glyph wants that glass. The law and the
`HeaderKeyChrome` switch behind it are in design-grammar.
**All three catalogs share that one chrome now** — the search surface's
hand-laid `.principal` row and its `""`/`.inline` title exception died with the
tab (2026-08-02). ⚠️ **A tab root must NOT hide its navigation bar.** The
original reason retired with `.searchable` (hiding it left the field with
nowhere to fall back to, build 135's invisible input, and the scope bar nothing
to attach to, build 140) — the rule stands on what the bar still carries: the
large title, both keys, and the Dynamic-Type reflow the old hand rules policed.
`CatalogTabHeader` is DELETED and Today's hand-rolled twin with it.

**Today's own laws moved to `today-rail.md`** (2026-08-02) — the header band's
pin, the date-first rail and its anytime entry, history's month landmarks, and
the pull's answer. They are one surface's layout, not tab-bar or search
architecture, and they were loading on every file under `PlusPlus/Views/**` to
say so. That file is scoped to `TodayView.swift` + `AnytimeCard.swift`. Read it
before touching Today; the one law that stays HERE is the tab-root chrome above,
which binds all four roots.

## Landings and the entrance flash

Every add from any surface LANDS on its list with the entrance flash
(`RoutineArrival`/`ExerciseArrival`/`EquipmentArrival` + `RowEntranceFlash` —
one landing for every add; cross-tab delivery is the pending-SLOT law above).
⚠️ **The flash is a leading GUTTER MARK on the row BACKGROUND, never a ring in
an overlay** (2026-07-28): a 3 pt accent capsule 5 pt in from the screen edge,
growing from its centre then fading. A background gets the row's true
full-bleed bounds free (an overlay has to GUESS them), the leading margin never
holds content, and it sits UNDER the swipe actions. Reduce Motion drops the
bloom ONLY; the flash itself is never gated. ⚠️ The mark's view exists only
while the arrival id is set, so **the owning surface must hold that id for
`RowEntranceFlash.totalDuration`** — clearing early unmounts the mark
mid-fade. See docs/DECISIONS.md 2026-07-28.
