---
paths:
  - "PlusPlus/Views/CatalogScopeView.swift"
  - "PlusPlus/Views/CatalogFrontPage.swift"
  - "PlusPlus/Views/CatalogFilterState.swift"
  - "PlusPlus/Views/FindOrCreateEngine.swift"
  - "PlusPlus/Views/ExerciseFilterState.swift"
  - "PlusPlus/Views/Components/FilterChips.swift"
  - "PlusPlus/Views/Components/CatalogItemRow.swift"
  - "PlusPlus/Views/Components/MissingEquipmentDisclosure.swift"
---

# The catalog's scopes, tiers, facets and front matter

Split out of `navigation.md` 2026-08-02, the way `today-rail.md` came out of
it the same day and for the same reason: these are ONE surface's content
laws, not tab-bar or search architecture, and at 9 KB they were loading on
every file under `PlusPlus/Views/**` to say so. The split is what the agent-doc
budget asks for when a file binds (`kit-test`'s first step) — the limit is not
raised, the scope is narrowed.

⚠️ The CONTAINER laws still live in `navigation.md` and still bind here: the
facet row's pinned-header seat and its search-surface seating, the scope
control, the tab-root chrome, and the landing/entrance-flash rules. Read that
file too before changing where any of this sits. Siblings: `design-grammar.md`
(the chip and tag anatomy these laws assume), `app-surfaces.md` (what each
screen is).

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
  ⚠️ **On the SEARCH surface that header starts in its PINNED seat**
  (2026-08-02): a `.plain` List pads above its first section header and that
  padding SCROLLS, so the row began 22 pt low and only arrived after 22 pt of
  travel — and the nav bar's scrolled-under hairline was visible for exactly
  that window, because the seated row's opaque band lands ON the line and
  occludes it (the 4 pt you see under the line is `FacetChip`'s 44 pt hit
  frame around its 36 pt cap). Closed with `listSectionSpacing(.custom(0))` +
  `contentMargins(.top, 0, for: .scrollContent)`, both, gated to
  `isSearchSurface`. ⚠️ Do NOT close it on the other four roots — the system
  large title travels through that space. ⚠️ And do NOT reach for a top
  `scrollEdgeEffectStyle` to kill the hairline: seating the row IS the fix,
  and the line never draws at offset 0. Typing
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
  shipped with is MOOT (2026-08-02, the top-bar search round): there is no
  search tab to exclude, and "no query and no facet" already says it — a query
  is what makes a catalog a query surface now, whichever tab it is on. The
  reasoning it carried still binds: do not give the facet row a competing top
  block. Counts come from a
  DEDICATED `FindOrCreateEngine.outcome` pass at empty query held in `@State`
  and rebuilt on a key (scope · kit MEMBERSHIP · catalog sizes), never
  derived in `listBody` — a per-render count is the cost per-scope counts
  were retired over. Chips state the axis value's CATALOG total, not its
  kit-doable subset: a doable count reads "Carry · 0" on a kit with no
  loadable gear, and the statement already carries the kit frame.
- **The Kit scope's CATALOG tier is ordered by what a piece would OPEN**
  (2026-08-02, #251): unlock count descending, name as the tiebreak, and the
  row states it as an `opens N` tag in place of its "N exercises" one (MINE
  rows keep that one — a piece you have answers what it is FOR, one you
  don't answers what it would do for you; two numbers on a row is noise).
  Counts come from `CatalogReachCalculator.unlocks`, the same function
  `EquipmentDetailScreen`'s "+N" add beat reads, so the promise and the beat
  can never disagree. ⚠️ **EMPTY QUERY ONLY** — a query still ranks by score.
  ⚠️ It is a fixed principle on one tier, NOT a sort control returning by a
  side door: `SortChip` stays deleted and nothing offers a choice of order.
  ⚠️ The counts are passed IN as `[String: Int]`, never computed inside the
  scoring pass. An EMPTY map leaves the order as it arrived, which is what
  keeps the PRESENTED equipment catalog its flat alphabetical run: only the
  tab passes counts, and the NULL kit passes none either (it refuses every
  add, so ordering it by what it would open is a hundred propositions the
  surface cannot accept).
  ⚠️ **The ORDER is FROZEN for the visit, the TAGS are live.** `unlocks` is a
  function of the kit, so one swipe-ADD changes many other pieces' counts —
  and the leading swipe commits membership in place, so a live order would
  re-sort the tier under the thumb that just swiped and put the next swipe on
  a different row. That is the complaint the presented catalog's flat run
  exists to answer. The seed is taken on APPEAR only (`equipmentOrder`);
  leaving and returning re-sorts. The tags read a LIVE per-render map
  (`equipmentOpensCounts`, beside the exercise counts that already ride every
  render) because a number printed on a row has to be true when it is read.
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

