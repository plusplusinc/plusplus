---
paths:
  - "PlusPlus/Views/**"
---

# Tab bar, search, and scroll architecture

Every ⚠️ here is a law learned on device — the build number names the failing
build. Don't re-try retired mechanisms; docs/DECISIONS.md and git history hold
the post-mortems. A law tagged **(recheck: iOS 27)** encodes an OS-26 bug:
re-test it on the next major SDK before assuming it still binds. Siblings: `catalog-scopes.md` (what the catalog SHOWS: scopes, tiers,
facets — split out 2026-08-02), `today-rail.md` (Today's band, rail,
landmarks, pull — split out the same day), `design-grammar.md` (color/key/tag/copy laws),
`app-surfaces.md` (what each screen is), `ui-interaction.md` (gesture laws).

## The tab bar

**The chrome is the SYSTEM'S, and the bar carries THREE tabs** (2026-08-05,
prototype A of the structure exploration; the five-tab era ran 2026-07-26 →
08-05 — the hand-drawn `AppBottomBar` stays DELETED; scroll legibility,
home-indicator clearance and label alignment are all things a real tab bar
does for free). `TabView` = **Today · Browse · Search** (`Tab(role:
.search)`). Tabs name MODES (do · browse · find), never scopes: WHICH
catalog is the scope control's job (see below), and Browse +
search share ONE scope state, so each opens on the catalog the other was
looking at and a tab switch changes the mode, never the catalog.

- ⚠️ **The tab bar does NOT minimize on scroll** (Dave, 2026-07-27):
  `.tabBarMinimizeBehavior(.onScrollDown)` is GONE — it existed only to move
  the retired bottom accessory between placements. The `.soft` bottom scroll
  edge effect handles content passing under a full-size bar.
- ⚠️ **The bottom scroll edge effect is `.soft` on every scrolling tab root**
  — `.hard` (139, a full-width slab) and hiding it outright (148, read-through)
  are both RETIRED. Soft shows only where content is actually under the chrome. It goes ON THE
  SCROLLING CONTENT, never as a background on the bar (build 133's mistake).
- ⚠️ **Do NOT hide tabs while search is active.** `Tab.hidden(_:)` works and
  preserves state, but the bar does NOT REFLOW around hidden tabs — what's
  left is a full-width group capsule with the survivor rattling around alone
  (build 139, Dave's screenshot, five-tab era; the lesson outlives the bar
  that taught it).
- A native `Tab` item is not a view the app can decorate — per-scope counts
  can never ride tab labels (retired).
- ⚠️ **Anything that writes state during layout** (`.onGeometryChange`,
  `GeometryReader` + `PreferenceKey`) anywhere in the TabView subtree breaks
  the search-role morph on FIRST activation (nav-diag 4e; recheck: iOS 27).
  Measure from `UIFont` metrics, or read geometry WITHOUT writing state (the
  catalog bar-row width, and the scope control's own cell width). ⚠️ Not
  `OverflowCapsuleRow` — it writes `@State` from a `GeometryReader` and
  renders inside catalog rows, i.e. inside this very subtree; only its TAG
  widths come from `UIFont`.
- ⚠️ Because **a `Tab`'s content is its own view tree**, Browse and search
  are two live INSTANCES of the catalog, so every broadcast needs one named
  owner: `ownsLandings` (`tabKey == scope.tab.rawValue`; `FindScope.tab` is
  `.browse` for all three) makes BROWSE the consumer of arrivals and Operator
  pushes, never "whichever instance shows that scope" — a landing switches
  away from search by definition. ⚠️ And because a tab's content is built on
  FIRST selection, a notification alone reaches nobody on a never-visited
  tab — every cross-tab landing rides a pending SLOT consumed on receive OR
  on appear (`RoutineArrival`, `OperatorArrival`); a bare post is the
  build-76 silent-dead-tap class. A landing also DIALS the shared scope
  (`RootTabView.land(on:scope:)`), so the list the entrance flash plays on is
  the one on screen. The query is search's and dies with it.
- ⚠️ **Scroll-position sync between a catalog tab and search is RETIRED**
  (tried in 139): `.scrollPosition(id:)` doesn't take on a `List` the way it
  does on `ScrollView` + `scrollTargetLayout()`, and the remaining route
  observes scroll GEOMETRY — the documented way to break the morph.

## One view: CatalogScopeView

**Browse and the search scopes are ONE view** (2026-07-25; the catalog tabs
collapsed into Browse 2026-08-05). Dialling the scope to **Routines** with
search closed and with it open land on the same screen: `CatalogScopeView`.
Search adds a QUERY, never a destination — `RootTabView` mounts two
instances (Browse and search) over one shared `scope`, keying nothing on
`searching`. It replaced `RoutineListView` / `ExercisesTabView` /
`EquipmentTabView` / `FindOrCreateView` AND the pushed
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
- **A catalog root carries no title** (Dave, 2026-07-26 for search; extended
  to Browse 2026-08-05): the scope control names the catalog, and on search a
  large title FLASHES on entry then collapses as search presents.
  `.navigationTitle("")` + `.inline` on both; Today keeps `.large`. The bar
  itself stays — hiding it is what left `.searchable` with nowhere to fall
  back to. ⚠️ The title's departure is why both roots seat the facet row in
  its pinned position from rest (`listSectionSpacing(.custom(0))` +
  `contentMargins(.top, 0)` — the 2026-08-02 law, widened from search-only):
  nothing travels through that space any more. If a large title ever returns
  to a catalog root, un-seat that root or you re-open the #521 class.
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

**Scope selection is an APP-DRAWN, FLAT segmented control**
(`ScopeSegmentedControl`): a recessed track spanning the control
(`Theme.surface` + `Theme.border` at `keyRadius`), with the selected scope
wearing the app's ONE selection look — `selectedTint` ground + `selectedRing`
+ `selectedInk` label — on a pill INSET 3 pt inside it. It rides the
NAVIGATION BAR's principal row on BOTH catalog roots, between the ++ key and
the kit switcher, the slot other roots put their title in — which on these
surfaces the control effectively is. Selecting SLIDES the pill
(`Theme.Anim.selection`, the selection-slides law). There is NO press
response, deliberately: a flat control's state flip is its feedback. Cells
stack icon OVER label, carry `.accessibilityLabel` + `.isSelected` (the
segmented-control a11y model) and per-INSTANCE
`findScope-<raw>-<browse|search>` identifiers (both roots stay mounted over
one scope, and an inactive tab's elements answer queries — the kit switchers
went per-instance for the same reason). Every segment is on screen at once,
so the smoke helper just taps a cell.

- ⚠️ **It was RAISED for one build (193) and is flat again** (Dave,
  2026-08-06, same day: "let's kill the 3d for the segmented control").
  The raised version wore a cap on a plate, sliding and sinking like its
  neighbours, and carried two deliberate deviations —
  flat-controls-stay-flat suspended, and the ONE selection look's ground
  replaced by elevation. **Both are RETIRED, and the reason is worth
  keeping.** On device it read cramped, and the containment was the fault:
  the ++ key and the kit switcher are caps sitting DIRECTLY on the bar,
  while this sat in a well — a fourth shape neither neighbour has. So the
  cap anatomy matched and the control still read as a different species,
  because "same family" was never about the cap. Matching a raised
  neighbour does not require being raised.
- ⚠️ **The pill's radius is `keyRadius - inset`, not `keyRadius`.**
  Concentric corners must be the outer radius minus the gap or the curves
  visibly disagree. The raised version had cap and well both at `keyRadius`
  about a point apart — the same fault design-grammar records the
  sheet-corner experiment being reverted for.
- ⚠️ **The "do NOT hand-roll a segmented control" law below still stands,
  and does not bind here.** It forbids faking iOS 26's interactive glass,
  which belongs to tab bars and native segmented controls alone. This one
  isn't trying to look native — it wears app chrome on purpose, which a
  `UISegmentedControl` cannot be made to do. Wearing app chrome also drops
  the platform limit that shaped every earlier version: a `UISegmentedControl`
  segment takes a title OR an image, never both (DTS-confirmed), which is why
  the 2026-07-26 control was GLYPHS-only. A view the app draws has no such
  rule; the icon-over-label stack is now a WIDTH choice, kept because it is
  the proven fit for this row.
- ⚠️ **Cell width is a PURE `GeometryReader` read**, used inline and never
  written to `@State`, taken from a `.background` so it cannot influence the
  size it measures — a layout-fed write anywhere in the TabView subtree is
  nav-diag 4e's morph killer. ⚠️ And the ROOT is the cells, not a
  `GeometryReader`: a reader has no ideal size, so on the pass where the bar
  row's width is unknown it collapses the control to a stub, and on the
  search tab that pass IS the first activation.
- ⚠️ **The pill's slide is app-authored animation inside a bar item**, the one
  thing build 138 saw fail (a `matchedGeometryEffect` pill refused to travel
  inside `tabViewBottomAccessory`). Two reasons to expect better: a
  `.principal` item is a title view the app FILLS, not a system-owned
  container, and this animates a plain `.offset` on a value rather than
  matching geometry across identities. #1 device check for this control — if
  it teleports, drop the animation, not the control.
- **The one-build `ScopeWheel` it replaced** (2026-08-05) was a horizontal
  take on the picker wheel, reviving #447's `InlineWheelPicker`. It went for
  a LOOK reason, not a mechanism one: nothing in the row it sat in wheeled.
  Its own laws died with it — the settle-only commit, the
  `scopeWheel-<instance>` track and the smoke helper's swipe fallback, the
  `.scrollPosition(id:)`/`.onScrollPhaseChange` scroll-into-state mirror.
  Don't re-derive them; a control that doesn't scroll has none of those
  problems.

- ⚠️ **A catalog root builds that row ITSELF**: one `.principal`
  `ToolbarItem` holding all three pieces at an explicit `width - 32`, with no
  leading or trailing items. A principal item is a TITLE VIEW, and UIKit centres
  it in the BAR, not between the side items — so ANY side item makes the two
  gaps asymmetric by its own width, and `.frame(maxWidth: .infinity)` cannot
  fix it (the bar proposes unbounded width). With no side items the title view
  gets the whole bar and every gap is the app's. The width is a PURE
  `GeometryReader` read (never written to state) — the closure re-runs on
  size changes and rebuilding re-runs the ranking pipeline, acceptable only
  because the bar never minimizes, so the size holds still mid-scroll. No
  hard `minWidth` on the control (an `HStack` already caps a flexible sibling;
  a floor makes the ROW overflow and shear keys off a narrow screen), an
  OPTIONAL width so a zero-size first pass leaves the row at its ideal size,
  and `.padding(.bottom, 4)` on the scope control. ⚠️ **The pad is a function
  of whether the control has a PLATE, not of taste.** `RaisedKeyStyle` pads
  each key by its travel, so a key's visible cap occupies the TOP 44 of a
  48 pt box. A FLAT control is 44 and needs that 4 pt beneath it to share the
  caps' baseline — true of the wheel, and true again since the 2026-08-06
  flatten. It was correctly ABSENT for the one build the control was raised
  and drew its own plate, where it would have counted the travel twice.
  Height and pad are one decision; check `RaisedKey.swift` before touching
  either.
- ⚠️ Two modifiers make an own-chrome control legal in a toolbar at all:
  `.sharedBackgroundVisibility(.hidden)` on the item (the control brings its
  own track; the toolbar's shared glass would wrap it in a second shape, and
  after the flatten that capsule would be the ONLY container in the row —
  which is exactly what the flatten removed) and
  `.searchPresentationToolbarBehavior(.avoidHidingContent)` on the search
  presentation. The control also caps its Dynamic Type at `accessibility1` —
  chrome sharing a bar with two keys can't grow without bound.
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
  ⚠️ **Do NOT hand-roll a segmented-control LOOKALIKE** — iOS 26's
  interactive glass belongs to tab bars and SEGMENTED CONTROLS alone, so an
  app-drawn pill-track can never look native. `ScopeSegmentedControl` is
  deliberately NOT that (see the section above): it wears the app's raised-key
  chrome, so it is a segmented control the app OWNS rather than one imitating
  the system. Remaining escape if the principal row ever fails: Photos'
  `.bottomBar` item with `.sharedBackgroundVisibility(.hidden)` +
  `.controlSize(.large)`.
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

## Tab roots and scroll

A **tab root** wears the SYSTEM navigation bar. Today: `.navigationTitle` +
`.large`, the ++ key (`AppMenuKey`) as a leading `ToolbarItem` and no
trailing accessory — every start lives on the rail (the anytime card's sport
keys + Train) or on a routine's own card. The two catalog roots: no title
and ONE `.principal` item holding ++ key · scope control · kit switcher (the
scope-control laws above). Every own-chrome bar item carries
**`.sharedBackgroundVisibility(.hidden)`** — raised keys and the scope
control bring
their own chrome and would otherwise nest inside the toolbar's shared glass
(a box in a box). ⚠️ **A tab root must NOT hide its navigation bar.**
`.searchable` belongs to that bar's presentation, so hiding it left the
field with nowhere to fall back to (build 135's invisible input) and the
scope presentation nothing to attach to (build 140). `CatalogTabHeader` is
DELETED and Today's hand-rolled twin with it; the system bar handles the
Dynamic-Type reflow the old hand rules policed.

**Today's own laws moved to `today-rail.md`** (2026-08-02) — the header band's
pin, the date-first rail and its anytime entry, history's month landmarks, and
the pull's answer. They are one surface's layout, not tab-bar or search
architecture, and they were loading on every file under `PlusPlus/Views/**` to
say so. That file is scoped to `TodayView.swift` + `AnytimeCard.swift`. Read it
before touching Today; the one law that stays HERE is the tab-root chrome above,
which binds all three roots.

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
