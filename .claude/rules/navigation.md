---
paths:
  - "PlusPlus/Views/**"
---

# Surface list, search, and scroll architecture

Every ⚠️ here is a law learned on device — the build number names the failing
build. Don't re-try retired mechanisms; docs/DECISIONS.md and git history hold
the post-mortems. A law tagged **(recheck: iOS 27)** encodes an OS-26 bug:
re-test it on the next major SDK before assuming it still binds.
⚠️ **One retirement WAS reversed** (native `.searchScopes`, 2026-08-04) and it
is the model for how: not "we tried again", but "the precondition the failure
depended on no longer exists, and here is what removed it". Anything less than
that is re-treading a build that already failed. Siblings: `catalog-scopes.md` (what the catalog SHOWS: scopes, tiers,
facets — split out 2026-08-02), `today-rail.md` (Today's band, rail,
landmarks, pull — split out the same day), `design-grammar.md` (color/key/tag/copy laws),
`app-surfaces.md` (what each screen is), `ui-interaction.md` (gesture laws).

## The surface list (there is no tab bar)

**The app has TWO roots, and the picker is a vertical list at the top of the
reveal drawer** (Dave, 2026-08-04): **Today · Search** (`DrawerNavList`, in
`Views/Components/`). Routines, Exercises and Kit are not missing from that
list — they are the search surface's SCOPES. An empty query has always shown a
scope's whole list and all three have rendered one `CatalogScopeView` since
2026-07-25, so a scope tap lands on exactly the screen a tab tap used to.

- ⚠️ **Still a `TabView`, with `.toolbar(.hidden, for: .tabBar)` on each
  root's content** — not a `switch` on the selection. A switch RE-MOUNTS, which
  drops Today's push stack and scroll position on every round trip through
  search, and `TodayView` is the app's most expensive body. `TabView` keeps
  both roots alive and builds each on first selection. The hide goes on the
  CONTENT, never on the `TabView` (`.toolbarBackground` at that level is a
  documented iOS 26 no-op and visibility is the same family). Fallbacks in
  order if a residual bottom inset shows on device: move it inside each root's
  own `NavigationStack`, then the `switch`.
- ⚠️ **Two different key strings, and they are NOT interchangeable.** The
  reveal drawer's swipe gate keys on the SURFACE (`"today"`/`"search"`,
  `reveal.activeTab`, matching what each root reports via `revealRoot(tab:)`).
  Operator's view-context keys on the CATALOG (`FindScope.contextKey` →
  `"routines"`/`"exercises"`/`"equipment"`). Those three are FROZEN: they were
  `AppTab`'s raw values, `OperatorChips` is unit-tested against them, and
  "equipment" is the frozen internal the vocabulary law names. They only ever
  looked like one string because surfaces and catalogs used to be one thing.
- ⚠️ `OperatorDestination`'s case names (`exercisesTab`, `equipmentTab`) are
  PERSISTED thread data — the receipt round-trips them through Codable.
  Renaming them is a stored-data migration, not a refactor; the mapping to
  surface + scope lives in `RootTabView`'s receiver instead.
- ⚠️ **The bottom scroll edge effect is `.soft` on every scrolling root**
  — `.hard` (139, a full-width slab) and hiding it outright (148, read-through)
  are both RETIRED. It goes ON THE SCROLLING CONTENT, never as a background on
  chrome (build 133's mistake). It still earns its keep with the bar gone:
  content now runs to the home indicator, and Today's floating search key sits
  over it.
- ⚠️ **Landings still ride a pending SLOT**, consumed on receive OR on appear
  (`RoutineArrival`, `OperatorArrival`). A root's content is built on FIRST
  selection, so a bare post reaches nobody on a never-visited surface — the
  build-76 silent-dead-tap class, unchanged by the tab bar's removal.
  `ownsLandings` simplified to `mode.isTab` (there is one root instance now,
  where there used to be four live ones needing a named owner), but the slots
  did NOT.
- ⚠️ **A landing sets the SCOPE before the SURFACE.** The search root reads
  `scope` when it builds, so the other order renders one frame of the outgoing
  catalog — the flash the three literal-scope tabs existed to avoid.
  `land(on:scope:)` is the only place that ordering lives.
- **Retired with the bar, and NOT to be re-tried on their old terms:**
  `.tabBarMinimizeBehavior(.onScrollDown)` (only ever moved the bottom
  accessory between placements), `Tab.hidden(_:)` for hiding catalogs during
  search (the bar does not REFLOW around hidden tabs — build 139, Dave's
  screenshot), per-scope counts on tab labels (a native `Tab` item is not a
  view the app can decorate), and scroll-position sync between a catalog and
  search (139: `.scrollPosition(id:)` doesn't take on a `List`, and the
  remaining route observed scroll geometry).
- ⚠️ **The state-write-during-layout law is REPEALED, and only because its
  cause is gone.** `.onGeometryChange` / `GeometryReader` + `PreferenceKey`
  anywhere in the TabView subtree used to break the `Tab(role: .search)` morph
  on first activation (nav-diag 4e). There is no search-role tab and no morph,
  so the hazard has no mechanism. ⚠️ Do not read this as "geometry probes are
  free" — `today-rail.md`'s anchor still derives its height from `UIFont` for
  its own reasons, and `catalog-scopes.md` still forbids probes on the facet
  row. If a search-role tab ever returns, this law returns with it.

## One view: CatalogScopeView

**The catalogs and the search scopes are ONE view** (2026-07-25, and it is
what made 2026-08-04 possible at all): scoping to **Routines** lands on
`CatalogScopeView`, the same screen the Routines tab used to be. Search adds a
QUERY, never a destination. It replaced `RoutineListView` /
`ExercisesTabView` / `EquipmentTabView` / `FindOrCreateView` AND the pushed
`EquipmentCatalogScreen`; the same view serves as a `.tab` (the search ROOT
now — its own stack, query bound from `RootTabView` so a landing can clear it)
and `.presented(setupMode:)` (pushed chrome + its own header field + an item
destination, #291) — the second is what onboarding step 1, the drawer's "Edit
your kit", the picker's filter escape and the template gear-check open.

**The PRESENTED equipment catalog is one flat alphabetical run**, while the
Kit TAB groups MINE/CATALOG (2026-07-25). Deliberate: the presented form is
the ADD surface, and with tiers every quick-add lifts the row you just swiped
to the top and shifts the rows under your thumb — worst in onboarding step 1.
The in-kit checkmark carries membership there.

## The search surface

The field is the NATIVE `.searchable` (2026-07-24, Dave — superseding the
custom bottom-bar takeover), placed INSIDE the search root's stack (placement
B) so its prompt can read the scope. Since 2026-08-04 it takes its ORDINARY
`.navigationBarDrawer` placement at the top, because the bottom morph belonged
to `Tab(role: .search)` and that tab is gone. The placeholder is per-scope
(`FindScope.searchNoun` — "Search routines / exercises / equipment").

- ⚠️ **This surface PRESENTS search on appear** (`isPresented`, set in
  `onAppear`, every time). Load-bearing, not eager:
  `.searchScopes(activation: .onSearchPresentation)` draws the scope bar only
  while search is presented, and the scope bar is the only way to change
  catalog — unpresented, the surface shows one catalog with no route to the
  other two. "Presented" is this root's RESTING state; an empty query is the
  norm. Cancelling is not fought (it leaves the plain list with the field
  above; tapping the field brings the scopes back), which is why the on-appear
  set is unconditional.
- ⚠️ **Presented, NOT focused.** `searchFieldFocused` is bound and set false
  beside the presentation, so arriving does not raise the keyboard over the
  list you asked to see. The old "never auto-focus" law
  (no `.tabViewSearchActivation(.searchTabSelection)`, build 144) existed
  because the bottom ACCESSORY did not rise with the keyboard and got buried;
  a scope bar directly under the field cannot be buried that way, so the
  keyboard is merely unwanted here, not fatal. **Whether presenting also
  focuses is device-only** — that binding is the lever if it does.
- **The SEARCH surface carries no title** (Dave, 2026-07-26): the scope bar
  names the catalog, and a large title FLASHES on entry then collapses as
  search presents. `.navigationTitle("")` + `.inline` there; Today keeps
  `.large`. The bar itself stays — hiding it is what left `.searchable` with
  nowhere to fall back to.
- ⚠️ **Four stacked bands above the list** — nav bar, field, scope bar, pinned
  facet row. Flagged, not yet judged; look at it on device before tuning. The
  cheapest levers in order: hide the facet row while the query is empty, then
  move the kit switcher into the drawer.
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
  the surface IS the scope (2026-07-25) all three catalogs create, so all three
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

**Scope selection is NATIVE `.searchScopes`, under the field** (2026-08-04),
after SEVEN builds in six app-placed homes. It is also the app's whole catalog
picker now — there is no resting way to change catalog that does not go
through it.

- ⚠️ **`activation: .onSearchPresentation`, never the `.automatic` default.**
  On iOS the default reveals scopes on TEXT ENTRY, which would show the
  catalog picker only after you had committed to searching one catalog —
  backwards, now that the scope bar is how you change catalog at all. This
  activation draws it the moment search presents, which is why the surface
  presents on appear (law above).
- ⚠️ **Why this is not a re-tried retired mechanism.** Native `.searchScopes`
  WAS retired on 140–143: it rendered exactly ONCE per app run and at the TOP,
  nowhere near the field. But that was a property of a BOTTOM-MORPHED field,
  and the morph came from `Tab(role: .search)`. No tab bar, no morph, no
  bottom field, no mismatch — the scope bar sits directly under the field in
  its ordinary place. **The precondition changed; the observation was never
  wrong.** If a search-role tab ever returns, so does the retirement.
  ⚠️ Still the #1 device check: does the bar draw on EVERY presentation, not
  just the first.
- **The segments carry WORDS** ("Routines · Exercises · Kit"). The glyph-only
  law was a WIDTH constraint of the retired `.principal` slot — a
  `UISegmentedControl` segment takes a title OR an image, never both
  (`.titleAndIcon` drops the icon; DTS-confirmed), and three words could not
  fit beside the ++ key and a variable-width kit switcher. A full-width scope
  bar has the room, and a word needs no `.accessibilityLabel` to be readable.
  The smoke helper still falls back to POSITION, as insurance only.
- ⚠️ **The bar's OTHER content still needs
  `.searchPresentationToolbarBehavior(.avoidHidingContent)`** — the ++ key and
  the kit switcher, on the one surface you reach them from.
- **`ScopeSegmentedControl` is KEPT, unused, as the fallback.** Reconstructing
  seven builds of placement work would be the expensive half of reverting; the
  file is the cheap half of keeping the option.
- **Retired app-placed homes, none to be re-tried on their old terms** —
  they were all answers to "where does the scope control go when the field is
  at the BOTTOM", a question that no longer exists (post-mortems:
  docs/DECISIONS.md + git). ⚠️ `tabViewBottomAccessory` does not rise with the
  keyboard (137–139, 144), and app-authored animation does not survive inside
  it (139). ⚠️ A `.bottomBar` `ToolbarItem` lands in the SAME ROW the field
  expands into (145) — Photos' recipe works only because its search is a small
  button there. ⚠️ A TOP `safeAreaInset` under the bar (147) was one row too
  many. ⚠️ The `.principal` row (150–169) needed a hand-measured width because
  a principal item is a TITLE VIEW and UIKit centres it in the BAR, not
  between the side items, so any side item made the two gaps asymmetric by its
  own width.
  ⚠️ **Do NOT hand-roll a segmented control** — iOS 26's interactive glass
  belongs to tab bars and SEGMENTED CONTROLS alone.
- The custom `SegmentedTabs` was RETIRED (2026-07-24) — every other former
  segmented site is native `Picker` (`.segmented` for short unit/mode toggles,
  a pushed `NavigationSelectRow` for multi-word modes).

## Scopes, tiers, and the missing-equipment group

**Moved to `catalog-scopes.md`** (2026-08-02) — scope/tier/facet/front-matter
laws are one surface's content rules and were loading on every view file to
say so, the same reasoning that split `today-rail.md` out. That file is scoped
to `CatalogScopeView` and its engine, state and row components. Read it before
touching what the catalog SHOWS; the laws about where the facet row SITS, and
about the scope control, stay here.

## Root chrome and scroll

A **root** wears the SYSTEM navigation bar — the ++ key (`AppMenuKey`) as a
leading `ToolbarItem` and the root's own accessory (the catalog's kit switcher)
as a trailing one. Today keeps `.navigationTitle("Today")` + `.large`; the
search root carries no title (law above). Today has no trailing key: every
start lives on the rail (the anytime card's sport keys + Train) or on a
routine's own card. Both keys carry
**`.sharedBackgroundVisibility(.hidden)`** — they bring their own raised-key
chrome and would otherwise nest inside the toolbar's shared glass (a box in a
box). ⚠️ **A root must NOT hide its navigation bar.** `.searchable` AND its
scope bar belong to that bar's presentation, so hiding it left the field with
nowhere to fall back to (build 135's invisible input) and the scope bar nothing
to attach to (build 140). `CatalogTabHeader` is DELETED and Today's
hand-rolled twin with it; the system bar handles the Dynamic-Type reflow the
old hand rules policed.

⚠️ **The ++ key is now the ONLY resting route to the drawer's surface list**,
so it is load-bearing in a way it was not while a tab bar existed — with the
leading-edge drag (`ui-interaction.md`) as the gesture twin. Today additionally
carries a **floating search key**, bottom-trailing: `HeaderIconButton` (44 pt
cap == hit frame, r11, `.raisedKey()`), identifier `todaySearchButton`. ⚠️ An
`.overlay`, never a `safeAreaInset` — an inset reserves a full-width band for
one key and shifts Today's landing geometry, which `today-rail.md` measures to
the point. It sits on the TRAILING edge so it never contends with the reveal
drawer's 16 pt leading strip, and it routes through
`RevealController.requestSurface` exactly as the drawer's own Search row does:
one route in, two doors.

**Today's own laws moved to `today-rail.md`** (2026-08-02) — the header band's
pin, the date-first rail and its anytime entry, history's month landmarks, and
the pull's answer. They are one surface's layout, not surface-list or search
architecture, and they were loading on every file under `PlusPlus/Views/**` to
say so. That file is scoped to `TodayView.swift` + `AnytimeCard.swift`. Read it
before touching Today; the one law that stays HERE is the root chrome above,
which binds both roots.

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
