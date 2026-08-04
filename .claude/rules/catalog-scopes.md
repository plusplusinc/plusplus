---
paths:
  - "PlusPlus/Views/CatalogScopeView.swift"
  - "PlusPlus/Views/CatalogFilterState.swift"
  - "PlusPlus/Views/FindOrCreateEngine.swift"
  - "PlusPlus/Views/ExerciseFilterState.swift"
  - "PlusPlus/Views/Components/FilterChips.swift"
  - "PlusPlus/Views/Components/CatalogItemRow.swift"
  - "PlusPlus/Views/Components/MissingEquipmentDisclosure.swift"
---

# The catalog's scopes, tiers and facets

Split out of `navigation.md` 2026-08-02, the way `today-rail.md` came out of
it the same day and for the same reason: these are ONE surface's content
laws, not tab-bar or search architecture, and they were loading on
every file under `PlusPlus/Views/**` to say so. The split is what the agent-doc
budget asks for when a file binds (`kit-test`'s first step) — the limit is not
raised, the scope is narrowed.

⚠️ The CONTAINER laws still live in `navigation.md` and still bind here: the
facet row's pinned-header seat and its search-surface seating, the scope
control, the tab-root chrome, and the landing/entrance-flash rules. Read that
file too before changing where any of this sits. Siblings: `design-grammar.md`
(the chip and tag anatomy these laws assume), `app-surfaces.md` (what each
screen is).

- **Today is a SURFACE, never a scope**: a timeline of derived state has
  nothing to narrow. `All` is GONE; an **empty query shows the scope's WHOLE
  list**. ⚠️ That law stopped being a convenience on 2026-08-04 and became
  STRUCTURAL: the three catalog tabs were retired precisely because a scope
  with no query already WAS the tab's list. Anything that makes an empty query
  show less than the whole list deletes a destination.
- **All three scopes read alike: MINE then CATALOG, plus ONE facet row**
  (filtering returned 2026-07-31, reversing 2026-07-25) — the Kit scope means
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
  ⚠️ **The header holds TWO rows on the root** (2026-08-04): the scope
  control, then the facets. `.listStyle(.plain)` pins one header, so they
  share it rather than compete for it. ⚠️ The `listSectionSpacing(.custom(0))`
  + `contentMargins(.top, 0)` pair that seated the row against the bar is
  GONE — it existed because the search surface had NO title, and the root
  wears the system LARGE title again (the scope's own name), which travels
  through exactly that space. Typing
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
  cross-surface arrival that needs gear expands the group so its entrance
  flash isn't on a hidden row.
- **The Kit scope's CATALOG tier is ordered by what a piece would OPEN**
  (2026-08-02, #251): unlock count descending, name as the tiebreak, and the
  row states it as an `Opens N` tag in place of its "N exercises" one (MINE
  rows keep that one — a piece you have answers what it is FOR, one you
  don't answers what it would do for you; two numbers on a row is noise).
  Counts come from `KitUnlocks.byPiece`, the same function
  `EquipmentDetailScreen`'s "+N" add beat reads, so the promise and the beat
  can never disagree. ⚠️ **EMPTY QUERY ONLY** — a query still ranks by score.
  ⚠️ It is a fixed principle on one tier, NOT a sort control returning by a
  side door: `SortChip` stays deleted and nothing offers a choice of order.
  ⚠️ The counts are passed IN as `[String: Int]`, computed on appear and
  never inside the scoring pass. An EMPTY map leaves the order as it arrived, which is what
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
  routine, `CatalogDetailViews`), and that is not a scope switch in a list.
- **Cross-scope discovery is the scope control itself** — never link rows,
  and per-scope result counts are GONE (2026-07-25: a glyph-only segment has
  nowhere to paint a number, and the central `matchCounts` costs a second
  ranking pass per keystroke). Prompts and empty states use
  `FindScope.searchNoun`, not `label`.

