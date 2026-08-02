---
paths:
  - "PlusPlus/Views/**"
---

# Tab bar, search, and scroll architecture

Every ⚠️ here is a law learned on device — the build number names the failing
build. Don't re-try retired mechanisms; docs/DECISIONS.md and git history hold
the post-mortems. A law tagged **(recheck: iOS 27)** encodes an OS-26 bug:
re-test it on the next major SDK before assuming it still binds. Siblings: `design-grammar.md` (color/key/tag/copy laws),
`app-surfaces.md` (what each screen is), `ui-interaction.md` (gesture laws).

## The tab bar

**The chrome is the SYSTEM'S, and the bar carries FIVE tabs** (2026-07-26 —
the hand-drawn `AppBottomBar` is DELETED after three device rounds; scroll
legibility, home-indicator clearance and label alignment are all things a real
tab bar does for free). `TabView` = **Today · Routines · Exercises · Kit ·
Search** (`Tab(role: .search)`).

- ⚠️ **The tab bar does NOT minimize on scroll** (Dave, 2026-07-27):
  `.tabBarMinimizeBehavior(.onScrollDown)` is GONE — it existed only to move
  the retired bottom accessory between placements. The `.soft` bottom scroll
  edge effect handles content passing under a full-size bar.
- ⚠️ **The bottom scroll edge effect is `.soft` on every scrolling tab root**
  — `.hard` (139, a full-width slab) and hiding it outright (148, read-through)
  are both RETIRED. Soft shows only where content is actually under the chrome. It goes ON THE
  SCROLLING CONTENT, never as a background on the bar (build 133's mistake).
- ⚠️ **Do NOT hide the catalog tabs while search is active.** `Tab.hidden(_:)`
  works and preserves state, but the bar does NOT REFLOW around hidden tabs —
  what's left is a full-width group capsule with Today rattling around alone
  (build 139, Dave's screenshot).
- A native `Tab` item is not a view the app can decorate — per-scope counts
  can never ride tab labels (retired).
- ⚠️ **Anything that writes state during layout** (`.onGeometryChange`,
  `GeometryReader` + `PreferenceKey`) anywhere in the TabView subtree breaks
  the search-role morph on FIRST activation (nav-diag 4e; recheck: iOS 27).
  Measure from `UIFont` metrics, or read geometry WITHOUT writing state
  (`ScopeSegmentedControl`'s width). ⚠️ Not `OverflowCapsuleRow` — it writes
  `@State` from a `GeometryReader` and renders inside catalog rows, i.e.
  inside this very subtree; only its TAG widths come from `UIFont`.
- ⚠️ Because **a `Tab`'s content is its own view tree**, the four
  catalog-showing tabs are four live INSTANCES, so every broadcast needs one
  named owner: `ownsLandings` (`tabKey == scope.tab.rawValue`) makes the
  catalog TAB the consumer of arrivals and Operator pushes, never "whichever
  instance shows that scope". ⚠️ And because a tab's content is built on FIRST
  selection, a notification alone reaches nobody on a never-visited tab —
  every cross-tab landing rides a pending SLOT consumed on receive OR on
  appear (`RoutineArrival`, `OperatorArrival`); a bare post is the build-76
  silent-dead-tap class. The three catalog tabs pass their scope as a LITERAL
  (shared state renders one frame of the outgoing catalog before
  `onChange(of: tab)` catches up); only the search tab reads `scope`, which is
  the point — search opens on the catalog you were already in. The query is
  search's and dies with it.
- ⚠️ **Scroll-position sync between a catalog tab and search is RETIRED**
  (tried in 139): `.scrollPosition(id:)` doesn't take on a `List` the way it
  does on `ScrollView` + `scrollTargetLayout()`, and the remaining route
  observes scroll GEOMETRY — the documented way to break the morph.

## One view: CatalogScopeView

**The catalog tabs and the search scopes are ONE view** (2026-07-25). Tapping
**Routines** with search closed and scoping to **Routines** with it open land
on the same screen: `CatalogScopeView`, one per `FindScope`. Search adds a
QUERY, never a destination — `RootTabView` mounts the three and shows them on
`tab` alone, keying nothing on `searching`. It replaced `RoutineListView` /
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

## The search surface

The field is the NATIVE `.searchable` (2026-07-24, Dave — superseding the
custom bottom-bar takeover), placed INSIDE the search tab's stack (placement
B) so its prompt can read the scope; the search-role tab morphs the tab bar
into the system field at the bottom, carrying the native clear (✕) and Cancel.
The placeholder is per-scope (`FindScope.searchNoun` — "Search routines /
exercises / equipment").

- **It does NOT auto-focus on entry**: no
  `.tabViewSearchActivation(.searchTabSelection)`, so the keyboard rises only
  on a field tap (`.searchFocused` is used solely for the "type a name first"
  refocus). ⚠️ That absence is LOAD-BEARING: **the bottom accessory does not
  rise with the keyboard**, so auto-raising it on arrival buries the scope
  control at the moment you land on it (build 144). There is NO custom Done
  key: leaving is a normal tab tap.
- ⚠️ **The iOS 26 morph bug is live** (recheck: iOS 27): an
  `.onGeometryChange` in the TabView
  subtree (a sibling tab's probe) can make the field fall back to the top
  `.navigationBarDrawer` placement on FIRST activation instead of morphing
  (nav-diag 4e). Since this surface HIDES the nav bar's title, the failure is
  NO visible field on first entry, not a top bar. #1 device check on the
  shipping OS; if it recurs, kill the morph trigger at its source, don't
  revert.
- ⚠️ **Fly-in on activation: read #539 first** (163-168, four causes ruled out
  by experiment and all reverted; the repro needs a TAB SWITCH).
- **The SEARCH surface carries no title** (Dave, 2026-07-26): the scope
  control names the catalog, and a large title FLASHES on entry then collapses
  as search presents. `.navigationTitle("")` + `.inline` there; the other four
  roots keep `.large`. The bar itself stays — hiding it is what left
  `.searchable` with nowhere to fall back to.
- ⚠️ **The bar's OTHER content needs
  `.searchPresentationToolbarBehavior(.avoidHidingContent)`** (iOS 17.1+) or
  activating search empties it — the system's `.automatic` clears the bar to
  give search room, which took the ++ key and kit switcher away on the one
  surface you reach them from.
- **Pushed catalogs, pickers, and sheets keep the expanding in-header field**
  (`HeaderSearchField`): a top-right magnifier expanding into a field spanning
  the row, an in-field `delete.left` CLEAR that keeps focus, and a separate
  `xmark` COLLAPSE key where the magnifier was; the centered title hides while
  searching. Both fields share ONE anatomy (`SearchFieldBody` — surface fill,
  borderStrong stroke, r11, mono text, the #233 one-shot focus intent).
  `xmark` is the COLLAPSE glyph here, which is why design-grammar's no-✕
  dismissal law exists.
- **Creation is the TOP list row, and the verb PREDICTS the tap**: **Create**
  (`New <object>` empty, `Create "<query>"` queried) COMMITS inline; **Add**
  OPENS something ("Add to routine…", the overview's "Add exercise"). Since
  the tab IS the scope (2026-07-25) all three catalogs create, so all three
  read alike — Kit's "Add … as equipment" was the one row that said Add and
  committed anyway, converged #507. Casing is `String.sentenceCasedFirst`.
  Empty results NEVER dead-end (the scopes law below covers what they show).
  The ONE thing that removes a
  create is an EXACT-name collision (2026-07-24): trimmed query
  case-insensitively equals an existing name → that type's create is
  suppressed (`FindOrCreateEngine.Collisions`), never a dead end since an
  exact match always ranks into results. Partial matches still offer create.
- `.listStyle(.plain)` PINS one header at a time; the catalog spends that pin
  on the FACET ROW (law below). A pinned header wears solid
  `Theme.background` — it occludes the rows beneath it.
- Search state on the universal surface is EPHEMERAL per-entry (a stale
  invisible query reads as data loss).
- **Return does not navigate** (Dave, 2026-07-26): submitting puts the
  keyboard away, it does not choose a result — no `onSubmit` action on any
  field in the app.

## The scope control

**Scope selection is the TAB BAR, and — on the search surface — a native
segmented `Picker` in the NAVIGATION BAR, between the ++ key and the kit
switcher** (`ScopeSegmentedControl`, settled 2026-07-26 after SEVEN builds in
six placements). That's the slot the other roots put their title in, which on
this surface the control effectively is.

- ⚠️ **The search surface builds that row ITSELF**: one `.principal`
  `ToolbarItem` holding all three pieces at an explicit `width - 32`, with no
  leading or trailing items. A principal item is a TITLE VIEW, and UIKit centres
  it in the BAR, not between the side items — so ANY side item makes the two
  gaps asymmetric by its own width, and `.frame(maxWidth: .infinity)` cannot
  fix it (the bar proposes unbounded width). With no side items the title view
  gets the whole bar and every gap is the app's. The width is a PURE
  `GeometryReader` read (never written to state), gated to this surface — the
  closure re-runs on height changes, and rebuilding re-runs the ranking
  pipeline, so a scrolling catalog would re-rank mid-scroll. No hard
  `minWidth` on the control (an `HStack` already caps a flexible sibling; a
  floor makes the ROW overflow and shear keys off a narrow screen), an
  OPTIONAL width so a zero-size first pass leaves the row at its ideal size,
  and `.padding(.bottom, 4)` because `RaisedKeyStyle` pads each key by its
  travel, seating caps 2 pt above the row's centre.
- ⚠️ **The segments are GLYPHS ONLY — a platform limit, not a preference**: a
  `UISegmentedControl` segment takes a title OR an image, never both
  (`.titleAndIcon` drops the icon; DTS-confirmed), and three words beside the
  ++ key and a variable-width kit switcher overflow the principal slot. Same
  symbols the tab bar uses for the same scopes. Each segment
  carries an explicit `.accessibilityLabel` (without it VoiceOver reads the
  symbol name); the smoke helper falls back to POSITION if the label doesn't
  reach XCUITest. It wears `.tint(Theme.background)` — a dark selected segment
  in dark mode (build 146 dropped the tint and got the inverse of the tab bar
  below; it's back) — and NO `.controlSize(.large)` (taller than the bar).
- ⚠️ Two modifiers make a segmented control legal in a toolbar at all:
  `.sharedBackgroundVisibility(.hidden)` on the item (it brings its own
  track; the toolbar's shared glass would wrap it in a second shape) and
  `.searchPresentationToolbarBehavior(.avoidHidingContent)` on the search
  presentation.
- **It is app-placed because every system-owned home failed** — four
  retired mechanisms, none to be re-tried (post-mortems: docs/DECISIONS.md
  + git, per this file's header). ⚠️ `tabViewBottomAccessory` does not rise
  with the keyboard (137–139, 144), and app-authored animation does not
  survive inside it (139). ⚠️ Native `.searchScopes` renders exactly ONCE
  per app run on a bottom-morphed search field, and at the TOP (140–143;
  four activation routes tried). ⚠️ A `.bottomBar` `ToolbarItem` lands in
  the SAME ROW the field expands into (145) — Photos' recipe works only
  because its search is a small button there. ⚠️ A TOP `safeAreaInset`
  under the bar (147) was one row too many. All four: recheck iOS 27.
  ⚠️ **Do NOT hand-roll the segmented control** — iOS 26's interactive
  glass belongs to tab bars and SEGMENTED CONTROLS alone. Remaining escape
  if the principal row ever fails: Photos' `.bottomBar` item with
  `.sharedBackgroundVisibility(.hidden)` + `.controlSize(.large)`.
- The custom `SegmentedTabs` was RETIRED (2026-07-24) — every other former
  segmented site is native `Picker` (`.segmented` for short unit/mode toggles,
  a pushed `NavigationSelectRow` for multi-word modes).

## Scopes, tiers, and the missing-equipment group

- **Today is a TAB, never a scope**: a timeline of derived state has nothing
  to narrow. `All` is GONE; an **empty query shows the scope's WHOLE list,
  grouped as its tab groups it**.
- **All three scopes read alike: MINE then CATALOG, plus ONE facet row**
  (filtering returned 2026-07-31, reversing 2026-07-25) — the Kit tab means
  "equipment, mine first", not "my kit". The row: single-select `FacetChip`
  Menus per scope (exercises kind · muscle · movement · mechanic · sides; kit
  type; routines focus · effort · style), state in `CatalogFilterState` —
  ephemeral per `CatalogScopeView` INSTANCE, reset on scope change, applied in
  `FindOrCreateEngine` so facets narrow and the query ranks.
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
  band law below states in full. PRESENTED and PICKER keep the pinned, opaque top
  `safeAreaInset` (app-drawn chrome); no geometry probes anywhere. Typing
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
- **Cross-scope discovery is the scope control itself** — never link rows,
  and per-scope result counts are GONE (2026-07-25: a glyph-only segment has
  nowhere to paint a number, and the central `matchCounts` costs a second
  ranking pass per keystroke). Prompts and empty states use
  `FindScope.searchNoun`, not `label`.

## Tab roots and scroll

A **tab root** wears the SYSTEM navigation bar — `.navigationTitle` +
`.navigationBarTitleDisplayMode(.large)`, the ++ key (`AppMenuKey`) as a
leading `ToolbarItem` and the root's own accessory (the catalogs' kit
switcher) as a trailing one — Today carries NONE: every start lives on the
rail (the anytime card's sport keys + Train) or on a routine's own card.
Both keys carry
**`.sharedBackgroundVisibility(.hidden)`** — they bring their own raised-key
chrome and would otherwise nest inside the toolbar's shared glass (a box in a
box). ⚠️ **A tab root must NOT hide its navigation bar.** `.searchable` AND
its scope bar belong to that bar's presentation, so hiding it left the field
with nowhere to fall back to (build 135's invisible input) and the scope bar
nothing to attach to (build 140). `CatalogTabHeader` is DELETED and Today's
hand-rolled twin with it; the system bar handles the Dynamic-Type reflow the
old hand rules policed.

- ⚠️ **Today's header band is FACTS ONLY (tally + `BlockBar`), pinned as
  the timeline's FIRST SECTION HEADER** — never a top `safeAreaInset`
  (build 162). ⚠️ **A pinned top inset costs the system large title**, on a
  `List` (#521) and a `ScrollView` (162) alike: it shifts the scroll's resting
  offset by the band's own height, the bar reads that as "already collapsed",
  and the title never draws at rest — a title-sized dead band sits where it
  should be. A section header lives inside the scroll's own layout, where the
  bar never sees it — the whole reason it works, and the facet row's mount too.
  The sticky-band era's machinery (`visualEffect` offset, reservation copy,
  anchor compensation) stays DELETED; the band keeps its OPAQUE background +
  hairline shelf, both BLED past the 16 pt column (`.padding(.horizontal,
  -16)`) since it sits inside a padded stack.
  ⚠️ **The band owns the pin OUTRIGHT** (Dave, build 162: "the band must
  pin at the top and not be usurped by anything else"). A scroll gets
  exactly ONE sticky header, so nothing else on Today may be a `Section` —
  the month landmarks were demoted to plain rows for this. ⚠️ **Its section
  holds the WEEK AHEAD too** (Dave, build 163: the bar "should always sit
  fully above the timeline, including future items") — a header renders where
  its section BEGINS, so with the future block above the section the band drew
  mid-rail. That block stays EAGER inside it as ONE `VStack` child: a
  `LazyVStack` sizes unrealized children approximately and the anchor sits
  below it (#267).
  ⚠️ Three riders, all invisible until they bite. The landing's anchor is a
  zero-LAYOUT overlay held one band-height ABOVE that block's bottom, its
  height DERIVED from `UIFont` (never probed — a state write here is the
  search-morph ban): `scrollTo` ignores pinned headers, so a bottom-seated
  anchor puts today's first row BEHIND the band. The below-anchor
  `minHeight` wraps below-anchor content ONLY, or content above the anchor
  eats it and a short timeline can't scroll today to the top. And the
  opening `scrollTo` is DEFERRED a runloop — against an id its lazy
  container hasn't created yet it is a silent no-op, one-shot flag
  already burned.
- ⚠️ **The rail is DATE-FIRST, and quick start is its ANYTIME entry**
  (Dave, build 161). Every dated entry renders its date on its OWN row,
  node CENTERED on it (both stand one node-diameter tall), card below;
  per-ENTRY, so two workouts one day print the day twice — what a log
  does. Today is ONE dated group ("today · thu · jul 31") holding the
  day's cards under one node; the carried lane's row is a plain past date
  in advisory amber (the "was" prefix retired 2026-08-01 — amber and
  position already read past tense); setup rows stay the one undated
  class. ⚠️ **A date row NEVER stands alone**: gate the whole ENTRY on
  having a card, or a day whose cards are all suppressed (carried work
  silences the rest-day card) leaves a dangling date. **The anytime entry
  sits below the future items and above today, every day**: "anytime" in
  the date position (the entry with no date), a SOLID node like every
  other (a dashed dot read as a rendering fault), and the dashed-shell
  `AnytimeCard` — the dash is the offer grammar, one idea with the future
  cards' "not yet" stroke. The landing seats the ANYTIME row under the
  band.
  ⚠️ The card's keys morph IN PLACE into their config panels
  (design-grammar's offer-morph law). The rack **WRAPS** (`FlowLayout`, equal
  pads, every pick a full key): the greedy `UIFont` fit and its "N more"
  overflow are DELETED — estimating what a layout can measure was the bug.
  The green + opens the picker SHEET (a multi-select is a searchable list).
- ⚠️ **Committed history's MONTH landmarks are plain ROWS** (#506, demoted
  build 162): grouped year+month, lowercase mono like every dateline
  (all-caps headings stay dead; a month is a DATE), year only when it
  isn't this one, spine drawing through, background bleeding past the
  16 pt column. They are NOT `Section` headers — the scroll's one pin
  belongs to the band (law above), and a second section would take it the
  moment history came into view.
- ⚠️ **The pull's answer (the refresh line) renders in the SPACE THE PULL
  OPENS**, not in the timeline — a zero-height `Color.clear` at the very top
  of the content with the line `.overlay(alignment: .bottom)` on it, so the
  line's bottom edge lands exactly on the content's top: above the first row,
  reserving nothing, clipped at rest. ⚠️ Plain alignment, not a custom guide (an
  `alignmentGuide(.top) { $0[.bottom] }` overlay was NOT honoured and collided
  with the week tally, 154; two earlier placements missed the gap entirely,
  153). It lives in the gap so it is
  visible only while the gap is open, and the system holds that open until
  the `refreshable` closure returns — the closure waits a beat before
  returning, a connected sync says "Syncing…" BEFORE the network, and
  clearing hangs off the closure's tail. ⚠️ **The system refresh SPINNER is
  killed** — same gap, two things in it is one too many; no hide API exists,
  so it draws in a clear tint (`.tint(.clear)` on the ScrollView,
  `.tint(Theme.textPrimary)` restoring the content's tint one level in).
  Today's is the app's only `.refreshable`. **Pull-to-refresh must not
  re-anchor the scroll** (`dayChangeToken` re-anchors, `dayToken` only
  re-derives): scrolling to today mid-gesture yanks the surface out from
  under the pull.

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
