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

**The chrome is the SYSTEM'S, and the bar carries FIVE tabs** (2026-07-26 —
the hand-drawn `AppBottomBar` is DELETED after three device rounds; scroll
legibility, home-indicator clearance and label alignment are all things a real
tab bar does for free). `TabView` = **Today · Routines · Exercises · Kit ·
Search** — five ORDINARY tabs. ⚠️ `Tab(role: .search)` was retired 2026-08-05
(Dave: put the input at the top): the role's separated circle and its morph of
the bar INTO the field are one package, and **that morph IS the bottom
placement**, so a top field and the role are two names for opposite things.
The Search tab now supplies its own label and magnifier — the role used to
provide both.

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
  `GeometryReader` + `PreferenceKey`) anywhere in the TabView subtree
  re-renders the TabView during initial layout (nav-diag 4e; recheck: iOS 27).
  The KNOWN casualty was the search-role morph on first activation, and the
  role is gone as of 2026-08-05 — ⚠️ read that as "the tripwire is gone", NOT
  "the hazard is". The finding was about geometry-driven state writes, and the
  morph is just the thing that was caught failing; nothing has shown the rest
  of the subtree is immune.
  Measure from `UIFont` metrics, or read geometry WITHOUT writing state
  (`RoutineDetailView.detailContent`'s width read — the live exemplar since
  `ScopeSegmentedControl`'s bar row was deleted 2026-08-05). ⚠️ Not `OverflowCapsuleRow` — it writes
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
  observes scroll GEOMETRY — the documented way to trip the layout-state-write
  hazard above (it was the morph that broke when 139 tried).

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
B) so its prompt can read the scope, and **at the TOP** in
`.navigationBarDrawer(displayMode: .always)` (2026-08-05, Dave). It carries
the native clear (✕) and Cancel. The placeholder is per-scope
(`FindScope.searchNoun` — "Search routines / exercises / equipment").

- ⚠️ **`displayMode: .always`, never `.automatic`.** The automatic drawer
  collapses the field away on scroll, and on the one surface where the field
  IS the point, a field that hides when the list moves is not a field.
- ⚠️ **The placement and the retired search role are ONE decision.** A drawer
  placement argued with `Tab(role: .search)` would have been arguing with the
  morph, which is itself the bottom placement; the role went so the placement
  could be uncontested. Do not re-add the role and keep the placement.
- **It does NOT auto-focus on entry**: the keyboard rises only on a field tap
  (`.searchFocused` is used solely for the "type a name first" refocus). ⚠️ The
  old justification (auto-raising buried the bottom accessory's scope control,
  build 144) died with the accessory AND the morph; what stands is Dave's, from
  2026-07-26 — you arrive with the whole surface in view. A drawer field is
  visible while unfocused, which the morphed one was not, so this costs less
  than it did. There is NO custom Done key: leaving is a normal tab tap.
- ⚠️ **The iOS 26 morph bug (nav-diag 4e) no longer has a morph to break**
  here, since the role is retired — but the top `.navigationBarDrawer` it used
  to fall BACK to is now the deliberate placement, so the tell has changed:
  the old failure showed as a field up top (or, while this surface hid its nav
  bar, no field at all). Do not read a top field as that bug now. The
  underlying hazard — state written during layout inside the TabView subtree —
  is unchanged and still binds (see the tab-bar section; recheck: iOS 27).
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

**Scope selection is the TAB BAR, and — on the search surface — an inline
horizontal WHEEL**: `InlineWheelPicker`, in the PINNED BAND directly under the
field, above the facet chips (2026-08-05, Dave). ⚠️ It is a RESTORE, not a new
control: it shipped on the Find-or-create surface 2026-07-24 (#447) and was
recovered from that pull request's own ref — squash merges had left it in no
reachable commit, so `git log --all` in a normal clone cannot see it. **When
something looks unrecoverable, check `refs/pull/<n>/head` before rebuilding it.**

- **Anatomy** (all device-tuned in #447 through an HTML prototype, so treat the
  constants as decided): a LEFT-anchored selection band whose leading edge sits
  on the 16 pt content column, sized INTRINSICALLY to the widest option label
  plus even padding and reserved chevron space (a hidden width-probe
  `PreferenceKey` — ⚠️ measuring the CELLS instead re-measures a fixed width and
  the band grows every render); white selected / grey unselected, **no blue** —
  selection reads by band and weight, not a pill; a soft 3D cylinder tilt
  (18°) that Reduce Motion flattens; faint in-band chevrons that step and fade
  while the wheel moves. Built on native scroll mechanics
  (`ScrollView(.horizontal)` + `.viewAligned` + `.scrollPosition(id:)`), so it
  can never overflow its viewport.
- ⚠️ **The accessibility model is the segmented control's, and it is
  load-bearing**: each option is a labelled `Button` with `.isSelected` (NOT
  one adjustable element, which would hide the per-option identifiers the smoke
  test needs); icons and chevrons are hidden from assistive tech; and
  VoiceOver's reveal-scroll is gated out of the scroll→selection sync
  (`accessibilityVoiceOverEnabled`) so NAVIGATING options cannot change the
  scope — only a tap or drag does.
- **Why not native `.searchScopes`** (which held this job for one day and
  WORKS — device-passed on 187, survived focus/blur on 188): it cannot be
  STYLED. Its entire public surface is a binding, an activation and tagged
  labels, so a system-drawn bar over app-drawn filter chips is two vocabularies
  with no way to converge them (Dave, 2026-08-05). ⚠️ The objection is styling,
  not behaviour — do not re-argue it from the 140–143 finding, which is dead
  (below).
- ⚠️ **The band under the field is what made this possible.** The control's
  seven-build history was entirely a consequence of the field being morphed out
  of the tab bar at the BOTTOM, leaving no container for a scope control that
  the keyboard did not bury. The field moved to the top drawer the same day, so
  the band the facet chips already pin in was free — and it is where a scope
  control belongs, next to the filters it sits with.
- ⚠️ **`.searchPresentationToolbarBehavior` is `.automatic`** (2026-08-05,
  Dave: focusing the input should hide the ++ key and the kit switcher so the
  field rises), REVERSING build 147's `.avoidHidingContent`. 147's reasoning
  does not bind: the scope control lived in the navigation bar then, so
  emptying that row took the only way to change catalogs with it. Scoping is in
  the band now, and what clears is two keys that each have a second door (the
  drawer opens on a leading-edge drag from any root; the kit is on every
  catalog tab).
- **The 140–143 "renders exactly ONCE per app run" finding is RETIRED**, on
  device: native scopes rendered and survived focus/blur on 187/188. ⚠️ WHY it
  failed then is still unknown — three things differed and 187 changed all
  three (the title went `.large` → `.inline`, the bar kept its content, the
  field moved to the drawer). Build 188 removed the bar-clearing one alone and
  the scope bar was unaffected, so **that** explanation is disproved; the
  `.inline` title and the placement remain untested candidates. Do not re-assert
  the bar-clearing story.
- **The retired containers stay retired** — post-mortems in docs/DECISIONS.md
  + git, per this file's header. ⚠️ `tabViewBottomAccessory` does not rise with
  the keyboard (137–139, 144), and app-authored animation does not survive
  inside it (139). ⚠️ A `.bottomBar` `ToolbarItem` lands in the SAME ROW the
  field expands into (145) — Photos' recipe works only because its search is a
  small button there. ⚠️ A TOP `safeAreaInset` under the bar (147) was one row
  too many. All three: recheck iOS 27.
  ⚠️ **Do NOT hand-roll a segmented control** — iOS 26's interactive glass
  belongs to tab bars and SEGMENTED CONTROLS alone, so an app-drawn one cannot
  look native however it is styled, and app-authored animation does not survive
  inside a system container (138).
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

**Today's own laws moved to `today-rail.md`** (2026-08-02) — the header band's
pin, the date-first rail and its anytime entry, history's month landmarks, and
the pull's answer. They are one surface's layout, not tab-bar or search
architecture, and they were loading on every file under `PlusPlus/Views/**` to
say so. That file is scoped to `TodayView.swift` + `AnytimeCard.swift`. Read it
before touching Today; the one law that stays HERE is the tab-root chrome above,
which binds all five roots.

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
