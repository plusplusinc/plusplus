---
paths:
  - "PlusPlus/**"
  - "PlusPlusWatch/**"
  - "PlusPlusWidgets/**"
  - "PlusPlusShared/**"
---

# App surface map + design grammar

The color/motion grammar, current since the Quiet Arcade refresh (full
reasoning in docs/DECISIONS.md, 2026-07-07 → 2026-07-10 entries):

- **Green is data/creation** (deltas, net chips, the ++ glyph, create
  affordances, the Start play key) — never chrome.
- **Blue (#1668D2/#5CA8F5) is selection/interactive state** — solid fills,
  one blue on screen outside a live ring gesture. `Theme.selected` is retired
  as a text/link color; escape hatches are quiet keys. On the superset rail
  (design handoff 2026-07-12 v2), blue is the MOMENT OF CREATING: the live
  ring highlight, and the landing animation (the selection field's reshape +
  snap, the pulse spark). The SETTLED superset return-loop rests in
  `Theme.supersetLoop`, an OPAQUE warm gray (`#7C786F`) a step more prominent
  than the neutral spine — a bound block is structure, not selection. (The
  first pass shipped a translucent resting blue, `selected.opacity(0.5)`,
  which composited with itself at the Canvas stroke overlaps and read
  blotchy; opaque ink strokes uniformly.)
- **Purple is done** (GitHub-merged mapping): the committed Today rail node
  (a FILLED purple checkmark circle — 2026-07-24; the seal lives on the rail
  dot, NOT on the committed card, reversing the 2026-07-14 on-card check and
  the build-33 "rail nodes are rings, never filled" rule — every OTHER
  timeline node stays a stroke-only ring, and all nodes share one 18 pt
  diameter so the row reads even), session pips, the finish checkmark, widget
  streak squares.
- **Amber (`Theme.notes`) is advisory, never alarm** — the warm in-between
  that is neither green (do/create) nor grey (inert). Two jobs: form-cue /
  "needs X gear" notes, AND a **carried-over occurrence** (2026-07-14) — a
  scheduled day that lapsed within the 6-day window shows in Today's
  carried-over lane (below today's cards, above history) as an amber
  tap-to-open card ("was wed · jul 22"), never a green due. The lane is
  UNLABELED (2026-07-23 round 2b: the rail's all-caps headings — TODAY ·
  CARRIED OVER · BEYOND THIS WEEK — died; the date line, cadence lines,
  and the cards' border/node/caption-tense grammar carry the structure).
  Green + one-click Start is reserved for TODAY's occurrence only; future
  and carried cards navigate to detail.
  Due-ness is anchored to `Routine.scheduleAnchor` — the LATER of
  `createdAt` and the last schedule change (`scheduleChangedAt`,
  2026-07-23 round 2b) — so a freshly added routine never carries a day
  it wasn't around for, and a freshly SET schedule never banks tomorrow
  against a completion that predates it (nor carries days older than the
  edit). The Kit split that backs this: `DueState.due` = scheduled today
  and unmet; `.missed(since:)` = a past scheduled day lapsed.
- **RaisedKey press grammar**: every committing/navigating button is an opaque
  cap depressing onto a fixed base plate (4 pt standard / 3 pt quiet, 0.06 s
  ease-out); flat controls (chips, toggles, segments, rows) stay flat.
  Custom key chrome everywhere — `pushedScreenChrome(...)` replaces system
  toolbars on pushed screens. **Icon-only keys are 11-pt ROUNDED SQUARES
  everywhere** (2026-07-19; the brief all-circles round of 2026-07-18, and the
  sheet-corner concentric experiment, were both reverted by Dave — the uneven
  concentric corners read wrong): `HeaderIconButton`/`HeaderMenuKey`/
  `AppMenuKey`/Operator send-stop use `RoundedRectangle(cornerRadius: 11)`
  (`ConfigIconButton` 8) + `.raisedKey()`. No per-context corner variation.
  Every "New …" / "Add …" / "Create …" list row is the shared `CreateRow` (a
  green bordered raised key), so creation reads as a button, not floating text.
  Keys that carry TEXT keep the rounded-rect pill: `QuietKey`,
  `LibrarySwitcherKey`, `SheetDismissKey`, the primary action bars.
- **One search UI + one sheet-dismissal, and ✕ means only "collapse search"**
  (2026-07-18; universal search 2026-07-23; **now `CatalogScopeView` + the
  bar's search key** — see the one-view bullet below, which supersedes the
  mechanism described here): cross-type search lived on a separate
  **Find-or-create surface** behind the tab bar's search item — the tab-root
  headers carry NO magnifier anymore. On that surface the field was the NATIVE `.searchable`
  (2026-07-24, Dave — superseding the custom bottom-bar takeover): placed
  INSIDE the search tab's stack (placement B) so its prompt can read the scope,
  the search-role tab morphs the tab bar into the system field at the bottom,
  carrying the native clear (✕) and Cancel. The placeholder is per-scope
  (`FindScope.searchNoun` — "Search routines / exercises / equipment") and it
  does NOT auto-focus on entry: no `.tabViewSearchActivation(.searchTabSelection)`,
  so the keyboard rises only on a field tap (`.searchFocused` is used solely for
  the "type a name first" refocus). ⚠️ That absence is now LOAD-BEARING, not
  just a preference: **the bottom accessory does not rise with the keyboard**,
  so auto-raising it on arrival buries the scope control at the moment you land
  on it (build 144). Build 143 tried the activation modifier to force a fresh
  native-scope presentation; scopes are gone and so is the reason. There is NO
  custom Done key: leaving is a normal tab tap. ⚠️ This re-arms the documented iOS 26 morph bug — an
  `.onGeometryChange` in the TabView subtree (TodayView's onboarding step-height
  probe, a sibling tab) can make the field fall back to the top
  `.navigationBarDrawer` placement on the FIRST activation instead of morphing
  (nav-diag 4e). And since this surface HIDES the nav bar, that fallback has
  nowhere to render — the failure is NO visible field on first entry, not a top
  bar. #1 device check on the shipping OS; if it recurs, kill the morph trigger
  at its source (rework the probe), don't revert. `SearchFieldBody` stays — the pushed catalogs/pickers/sheets
  still use it via `HeaderSearchField`. Pushed catalogs, pickers, and sheets keep the expanding
  in-header field (`HeaderSearchField`) — a top-right magnifier that expands
  into a field spanning the row, an in-field `delete.left` CLEAR that keeps
  focus, and a separate `xmark` COLLAPSE key where the magnifier was; the
  centered title hides while searching. Both share ONE field anatomy
  (`SearchFieldBody` — surface fill, borderStrong stroke, r11, mono text, the
  #233 one-shot focus intent). Because `xmark` is the collapse glyph, a
  sheet/tray NEVER dismisses with a ✕ — it uses a text `SheetDismissKey`
  ("Cancel" to abandon edits, "Done" view-only; Find-or-create's Done follows
  the same grammar). Creation is the TOP list row, verb-keyed: **Create**
  (`New <object>` / `Create "<query>"`) when it makes a custom object inline,
  **Add** (`Add <object>` / `Add "<query>"`) when it navigates. Since the tab
  IS the scope (2026-07-25) every catalog's top row CREATES inline — deep-linking
  into a pre-scoped search would mean navigating to where you already are, so
  `FindOrCreateLaunch` is gone and onboarding step 2 just lands on the Routines
  tab, which is the routine catalog (the standalone `RoutineCatalogScreen` was
  retired into it, 2026-07-24). Query casing
  is `String.sentenceCasedFirst`. Empty results NEVER dead-end: the create/add
  row is always present + a "Clear filters" `QuietKey` when facets are active.
  The ONE thing that removes a create is an EXACT-name collision (2026-07-24):
  when the trimmed query case-insensitively equals an existing item's name,
  that type's create is suppressed (Find-or-create; `FindOrCreateEngine.Collisions`)
  so the surface never offers to duplicate the row sitting right below it —
  never a dead end, because an exact match always ranks into results, so
  results are non-empty whenever a create is hidden. Partial matches still
  offer create.
  **Scope selection is the TAB BAR, and — on the search surface — a native
  segmented `Picker` in the NAVIGATION BAR, between the ++ key and the kit
  switcher** (`ScopeSegmentedControl`, settled 2026-07-26 after SEVEN builds in
  six placements). That's the slot the other four roots put their title in,
  which on this surface the control effectively is — it names the catalog, and
  the surface carries no title precisely so it can.
  ⚠️ **The search surface builds that row ITSELF**: one `.principal`
  `ToolbarItem` holding all three pieces at an explicit `width - 32`, with no
  leading or trailing items. A principal item is a TITLE VIEW, and UIKit centres
  a title view in the BAR rather than in the space between the side items — so
  its two gaps differ by exactly the difference in those items' widths (a 42 pt
  ++ key against a 78 pt kit switcher gave 76 pt left / 40 pt right), and that
  difference moves with the kit's name. `.frame(maxWidth: .infinity)` doesn't
  help: the bar proposes an unbounded width, so the control takes its ideal
  size. With no side items the title view gets the whole bar and every gap is
  the app's. The width is a PURE `GeometryReader` read (never written to state)
  and is gated to this surface — the closure re-runs on height changes too, and
  rebuilding the view re-runs the ranking pipeline, so a scrolling catalog would
  re-rank mid-scroll for a width it never uses. No hard `minWidth` on the
  control (an `HStack` already caps a flexible sibling at its share; a floor
  makes the ROW overflow and shear the keys off a narrow screen), an OPTIONAL
  width so a zero-size first pass leaves the row at its ideal size, and
  `.padding(.bottom, 4)` on the control because `RaisedKeyStyle` pads each key
  by its travel, seating their caps 2 pt above the row's centre.
  ⚠️ **The segments are GLYPHS ONLY, and that is a platform limit, not a
  preference**: on iOS a segmented control gives each segment a title OR an
  image and NEVER both (`NSSegmentedControl` can; `UISegmentedControl` can't),
  which Apple DTS confirmed for SwiftUI on forums thread 816517 —
  `.titleAndIcon` renders the title and drops the icon, and the HIG says pick
  one. So "icons too" means icons INSTEAD. They're the same symbols the tab bar
  uses for the same three scopes, and they're also the half that fits: three
  words beside the ++ key and a variable-width kit switcher overflow the
  principal slot, and a segmented control doesn't scroll, it truncates. Each
  segment carries an explicit `.accessibilityLabel` (without it VoiceOver reads
  the symbol name), and the smoke helper falls back to POSITION if that label
  doesn't reach XCUITest. It wears `.tint(Theme.background)` — a dark selected
  segment in dark mode, the stock lighter one in light — and takes NO
  `.controlSize(.large)` (that control is taller than the bar).
  ⚠️ Two modifiers make a segmented control legal in a toolbar at all:
  `.sharedBackgroundVisibility(.hidden)` on the item (it brings its own track,
  and the toolbar's shared glass would wrap that in a second shape) and
  `.searchPresentationToolbarBehavior(.avoidHidingContent)` on the search
  presentation (below) — without the second, activating search takes the
  control away with the rest of the bar's content.
  It is app-placed because every system-owned home failed a different way, and
  each failure is a law now:
  ⚠️ **`tabViewBottomAccessory` does not rise with the keyboard** (137–139,
  144) — search's own keyboard buries anything in it, and on that surface the
  keyboard is up most of the time you want to change scope.
  ⚠️ **Native `.searchScopes` renders exactly ONCE per app run** on a
  bottom-aligned field morphed out of `Tab(role: .search)` (140–143), and
  renders at the TOP, nowhere near the field. Tried four ways; still once.
  ⚠️ **A `.bottomBar` `ToolbarItem` lands in the SAME ROW the search-role
  field expands into** (145), so it sits behind the field. Photos' recipe works
  there only because Photos' search is a small BUTTON in that row, not a
  full-width field. The `.principal` slot has no such competition — the field
  expands out of the TAB BAR, nowhere near the navigation bar.
  ⚠️ **A TOP `safeAreaInset` under the bar** (147) was right but one row too
  many: a band holding a control, directly under a bar holding two keys with
  nothing between them.
  ⚠️ Build 146 dropped the `.tint` reasoning that a dark pill would vanish into
  the dark row it sits on. That ignored the system's own track BETWEEN the two,
  and left the default lighter-pill look — the inverse of the tab bar below. The
  tint is back; see above.
  ⚠️ **Native `.searchScopes` DOES NOT WORK on a bottom-aligned search field
  morphed out of a `Tab(role: .search)`** — it renders exactly ONCE per app run.
  Tried, in order, and all still once: `.onSearchPresentation` activation;
  `.searchable` moved INSIDE the navigation stack (the documented requirement,
  and the thing that made scopes appear at all); giving the surface a real
  navigation bar; and `.tabViewSearchActivation(.searchTabSelection)` so every
  arrival is a fresh presentation. It also renders at the TOP, nowhere near the
  field it scopes, and placement is not the app's to choose.
  ⚠️ **Do NOT hand-roll the segmented control.** iOS 26's interactive "bubbly"
  glass belongs to exactly TWO components, tab bars and SEGMENTED CONTROLS, so
  an app-drawn one cannot look native however styled (`ryanashcraft/FabBar`
  hosts a real `UISegmentedControl` for this reason). And **app-authored
  animation does not survive inside the accessory**: the accessory is a
  system-owned container that re-renders outside the app's transactions, so even
  the canonical `matchedGeometryEffect` pill with `.animation` on the value
  refused to travel on device (build 139).
  ⚠️ **The "double background" is PADDING, not the Picker.** The accessory
  always draws a Liquid Glass capsule and no API removes it; build 137's
  `.padding(.horizontal, 12)` inset the Picker's own segmented track inside that
  capsule, drawing two concentric shapes. Edge to edge the silhouettes coincide.
  `.controlSize(.large)` gives it the Photos proportions (r/SwiftUI 1o2vdp4); no
  `.tint`, so it wears the iOS 26 system look.
  **The SEARCH surface carries no title** (Dave, 2026-07-26): the scope control
  already names the catalog, and a large title FLASHES on entry then collapses
  as search presents, leaving an empty band. `.navigationTitle("")` + `.inline`
  there; the other four roots keep `.large`. The bar itself stays — hiding it is
  what left `.searchable` with nowhere to fall back to.
  ⚠️ **The bar's OTHER content needs `.searchPresentationToolbarBehavior(.avoidHidingContent)`**
  (iOS 17.1+) or activating search empties it: the system's `.automatic`
  behaviour is to clear the navigation bar and give search the room, which is
  the same mechanism that emptied the top band on build 143. Here that took the
  ++ key and the kit switcher away the moment you tapped the field — the drawer
  and the kit switch, gone, on the one surface you reach them from.
  (Photos' Years/Months/All is a THIRD thing again: a `.bottomBar` `ToolbarItem`
  with `.sharedBackgroundVisibility(.hidden)` + `.controlSize(.large)` — that
  modifier strips a toolbar item's shared glass and exists ONLY for toolbar
  items. The remaining escape if the accessory ever fails.)
  The custom `SegmentedTabs` was RETIRED (2026-07-24) —
  every other former segmented site moved to native `Picker` (`.segmented` for
  short unit/mode toggles, a pushed `NavigationSelectRow` for multi-word modes).
  **Kit availability is NOT a filter** (2026-07-25, superseding the "Doable"
  chip): nothing is HIDDEN by the active kit. What the kit can't do groups
  under a collapsible **"N exercises/routines require more equipment"**
  disclosure (`MissingEquipmentHeaderRow`, `Views/Components/`), placed AFTER
  the doable items, COLLAPSED BY DEFAULT (a whole-row toggle + chevron;
  `Theme.Anim.standard`). The header is a plain scrolling row (not pinned) in
  NEUTRAL ink — amber stays the per-row "needs X" advisory; an amber header
  reads as an alarm over a group. Header copy describes the ITEMS (they require
  the equipment), not the user, so it clears the no-obligation law; the one
  sentence lives in `MissingEquipmentPhrasing`. The SAME pattern is on all
  three surfaces that used to filter: Find-or-create results, the Exercises tab,
  and the Routines tab (which thereby loses its inline-everything flag-don't-hide
  for doable-first + a collapsed group — on Routines `.onMove` sits on the
  doable group only). In `FindOrCreateEngine` the split is a pure `.missing(noun:)`
  `Section.Kind` (All scope: capped doable overview then a missing group per
  type, which still shows when a type has ONLY missing results so an
  only-missing query never empties; scoped: MINE/CATALOG doable, then one
  uncapped missing group); collapse state is ephemeral per-surface `@State`,
  reset on entry, and a cross-tab arrival that needs gear expands the group so
  its entrance flash isn't on a hidden row.
  Results use real `List` `Section`s so `.listStyle(.plain)` PINS each heading
  to the top until the next takes over (one sticky at a time); the header wears
  a solid `Theme.background` so a pinned heading occludes the rows beneath it.
  Search state on the universal surface is EPHEMERAL per-entry (a stale
  invisible query reads as data loss); every add from it LANDS on its list
  with the entrance flash (`RoutineArrival`/`ExerciseArrival`/
  `EquipmentArrival` + `RowEntranceFlash` — one landing for every add).
- **The catalog tabs and the search scopes are ONE view** (2026-07-25 —
  supersedes the arrangement above wherever they differ). Tapping **Routines**
  with search closed and scoping to **Routines** with it open land on the same
  screen: `CatalogScopeView`, one per `FindScope`. Search adds a QUERY, never a
  destination — `RootTabView` mounts the three and shows them on `tab` alone,
  keying nothing on `searching`. It replaced `RoutineListView` /
  `ExercisesTabView` / `EquipmentTabView` / `FindOrCreateView` AND the pushed
  `EquipmentCatalogScreen`; the same view serves both as a `.tab` (own stack,
  query bound from the root because the field lives in the bar) and
  `.presented(setupMode:)` (pushed chrome + its own header field + an item
  destination, #291) — the second is what onboarding step 1, the drawer's
  "Edit your kit", the picker's filter escape and the template gear-check open.
  **The chrome is the SYSTEM'S, and the bar carries FIVE tabs** (2026-07-26 —
  the hand-drawn `AppBottomBar` is DELETED after three device rounds, the last
  of which produced scroll-through illegibility, no home-indicator clearance
  and misaligned labels in one go; all three are things a real tab bar does for
  free). `TabView` = **Today · Routines · Exercises · Kit · Search**
  (`Tab(role: .search)`). The catalogs spent one build (137) as a scope you
  dialled on a bottom-accessory wheel while the bar carried only Today and
  Search; they are tabs again, but now over ONE screen, which is what that
  round was really after. **All four catalog-showing tabs render the same
  `CatalogScopeView`** — a tab decides which catalog, never which screen.
  ⚠️ Because **a `Tab`'s content is its own view tree**, that is four live
  INSTANCES, so every broadcast needs one named owner: `ownsLandings`
  (`tabKey == scope.tab.rawValue`) makes the catalog TAB the consumer of
  arrivals and Operator pushes, never "whichever instance shows that scope"
  (the search tab dialled to routines shows routines too, and a landing
  switches away from search by definition). ⚠️ And because a tab's content is
  built on FIRST selection, a notification alone reaches nobody on a tab you
  have never visited — every cross-tab landing rides a pending SLOT consumed on
  receive OR on appear (`RoutineArrival` and now `OperatorArrival`); a bare
  post is the build-76 silent-dead-tap class. The three catalog tabs pass their
  scope as a LITERAL (reading shared state would render one frame of the
  outgoing catalog before `onChange(of: tab)` caught up); only the search tab
  reads `scope`, which is the point of the state — search opens on the catalog
  you were already in. The query is search's and dies with it: no other tab has
  a field, so a surviving query would filter a list with nothing on screen
  explaining it.
  ⚠️ **Do NOT hide the catalog tabs while search is active.** `Tab.hidden(_:)`
  works and preserves state, and it does put Today beside the morphed field —
  but the bar does NOT REFLOW around the hidden tabs, so what's left is a
  full-width group capsule with Today rattling around alone in it (build 139,
  Dave's screenshot). Which tab the system parks beside the field is the
  smaller problem. `searchActive` survives as the accessory's animated
  `isEnabled` only.
  ⚠️ **Scroll-position sync between a catalog tab and search does not work and
  is RETIRED** (tried in 139): `.scrollPosition(id:)` does not take on a `List`
  the way it does on a `ScrollView` + `scrollTargetLayout()`, and the remaining
  route observes scroll GEOMETRY, which is the documented way to break the
  search-role morph. Not worth that trade for a convenience.
  ⚠️ **The bottom scroll edge effect is `.soft` on every scrolling tab root** —
  the system's own gradient, and the THIRD answer this edge has had. `.hard`
  (139) was added because the bar's glass alone can't occlude rows passing
  under it (headings legible below the search field); it draws a full-width
  blurred SLAB for the bar to sit on, which Dave killed on 148. Hiding it
  outright (148) brought the read-through straight back — his own screenshot
  has an equipment name legible through the search field. Soft shows only where
  content is actually under the chrome, so there's no slab on an empty stretch.
  It goes on the SCROLLING CONTENT, never as a background on the bar — the
  mistake build 133 made.
  ⚠️ **The tab bar does NOT minimize on scroll** (Dave, 2026-07-27):
  `.tabBarMinimizeBehavior(.onScrollDown)` is GONE. It was only ever there to
  move the bottom accessory between its `.expanded` and `.inline` placements —
  which is what decided icon + label vs icon only on the old scope control —
  and the accessory died on 149. With nothing reading placement, all it did was
  shrink the bar out from under your thumb on the way down a catalog. The
  `.soft` bottom scroll edge effect is what handles content passing under a
  full-size bar. (Historic, for whoever brings an accessory back: accessory
  placement is READ-ONLY — `tabViewBottomAccessoryPlacement` is the system's
  choice, `.inline` means "beside a MINIMIZED bar", and the minimize behaviour
  is what moves between the two, so inline is a SCROLLED-DOWN state, never the
  resting one.) A native `Tab` item is
  also not a view the app can decorate (so per-scope counts can never ride tab
  labels — they are retired). ⚠️ Anything that writes state during layout
  (`.onGeometryChange`, `GeometryReader` + `PreferenceKey`) anywhere in the
  TabView subtree breaks the search-role morph on FIRST activation (nav-diag
  4e); measure from `UIFont` metrics instead, as `OverflowCapsuleRow` does.
  **Return does not navigate** (Dave, 2026-07-26): submitting a search puts the
  keyboard away, it does not choose a result — no `onSubmit` action on any
  field in the app now.
  **Today is a TAB, never a scope**: a timeline of derived state has nothing to
  narrow. `All` is GONE, and an **empty query shows the scope's WHOLE list,
  grouped as its tab groups it**. **All three scopes read alike: MINE then
  CATALOG, and NO facet chips** (Dave) — so the Kit tab means "equipment, mine
  first", not "my kit". The field replaces the retired chips: muscle groups sit
  in `ExerciseFilterState.searchHaystack` and equipment categories in the
  equipment scorer, so typing reaches them. The "require more equipment" group
  splits INSIDE each tier (`MISSING_MINE`/`MISSING_CATALOG`): MINE/CATALOG is
  the primary division, kit availability the secondary. Cross-scope discovery
  rides **per-scope result counts on the scope labels** (no number at rest),
  never link rows — and each surface publishes its OWN count by summing its own
  sections (a central `matchCounts` meant a second ranking pass per keystroke).
  Prompts and empty states use `FindScope.searchNoun`, not `label`: the Kit
  scope searches the equipment CATALOG, so it says "Search equipment".
- **One swipe law on every catalog row: LEADING is curation, TRAILING is
  destructive** (2026-07-25). Exercises lead FAV/UNFAV, trail DELETE on customs
  only; Kit leads ADD/REMOVE membership, trails DELETE on customs; Routines
  trail DELETE. Catalog templates have neither and are plain rows. **Row
  context menus are gone** — the swipes ARE those acts now, and on Routines a
  long press has to belong to `.onMove`. **Reorder is routines-only, tab-only,
  empty-query-only, MINE-tier-only**: a ranked or narrowed list has no order to
  write back, and writing one would destroy the user's drag-ordering. Routines
  render as **cardless rows** outside Today — a catalog list reads flat — but
  cardless is a CHROME decision: the row still renders the shared
  `RoutineCardContent` (title · `focus · schedule · effort · estimate` ·
  equipment tier), so it loses the card, never its facts. Templates render the
  same body from `RoutineMeta(focus:effort:estimate:gear:)`, so a template reads
  identically to the routine it becomes.
- **The PRESENTED equipment catalog is one flat alphabetical run**, while the
  Kit TAB groups MINE/CATALOG (2026-07-25). Deliberate: the presented form is
  the ADD surface, and with the tiers every quick-add lifts the row you just
  swiped to the top and shifts the rows under your thumb — worst in onboarding
  step 1, a run of eight adds. The in-kit checkmark carries membership there.
- **Heading treatment follows the nature of the title** (2026-07-18; the tab
  roots reworked 2026-07-26): a **tab root** wears the SYSTEM navigation bar —
  `.navigationTitle` + `.navigationBarTitleDisplayMode(.large)`, with the ++ key
  (`AppMenuKey`) as a leading `ToolbarItem` and the root's own accessory
  (Today's Start key, the catalogs' kit switcher) as a trailing one. Both keys
  carry **`.sharedBackgroundVisibility(.hidden)`**, since they bring their own
  raised-key chrome and would otherwise nest inside the toolbar's shared glass
  capsule — a box in a box, the same fault that killed the bottom accessory.
  ⚠️ **A tab root must NOT hide its navigation bar.** The hand-drawn
  `CatalogTabHeader` + `.toolbar(.hidden, for: .navigationBar)` cost three
  builds to unlearn: `.searchable` AND its scope bar belong to that bar's
  presentation, so hiding it left the field with nowhere to fall back to when
  the morph failed (build 135's invisible input) and the scope bar with nothing
  to attach to at all (build 140's missing scopes). `CatalogTabHeader` is
  DELETED and Today's hand-rolled twin with it; the system bar handles the
  Dynamic-Type reflow that the old `.layoutPriority(1)` / no-`.fixedSize` rules
  used to police by hand. ⚠️ **Today's WEEK STRIP (tally + `BlockBar`) is a
  STICKY band inside the scroll** (2026-07-27) — the scroll's first content,
  held at the visible top by a `visualEffect`
  (`offset(y: minY < 0 ? -minY : 0)` against `.scrollView`) that does nothing
  on overscroll, so it rides the rubber band. It spent one build PINNED between
  the bar and the scroll, and that broke the pull: content rubber-bands and
  UIKit walks the large title down with it, while a pinned strip stays exactly
  where it is, so "Today" slid over the block bar (Dave, build 152).
  **Anything a large title can travel over has to be scroll content** — a
  `safeAreaInset` is pinned too and fails the same way. Plain content isn't
  enough either: above the today anchor it is off-screen on arrival (the
  opening scroll seats today at the top), and below the anchor it scrolls away,
  which Dave rejected — he wanted main's always-there band, plus travel.
  ⚠️ That `visualEffect` is a pure render-time read (no state write), which is
  what keeps it clear of the morph law; `onScrollGeometryChange` is NOT.
  ⚠️ **A sticky band floats, so it stops reserving its space**: a hidden second
  copy (`weekStripBand.hidden()`) sits just below the today anchor so the
  opening `scrollTo` doesn't seat the date line under it — exact at every
  Dynamic Type size, no measuring, no constant. Floating also means the band
  needs an OPAQUE background (rows slide under it) and the 16 pt content column
  lives on the scroll stack's CHILDREN, not the stack, or rows show through the
  gutters. ⚠️ It does NOT ride the rail (Dave, reversing the first cut, which
  gave it a spine and no node like `beyondThisWeekBlock`): the screen's content
  column and a full-width bar, because the tally is the surface's week header,
  not an entry on the timeline. Same round: ⚠️ **the pull's own answer
  (the refresh line) renders in the SPACE THE PULL OPENS**, not in the
  timeline — an `overlay(alignment: .top)` with
  `alignmentGuide(.top) { $0[.bottom] }`, so it sits entirely above the first
  row, reserves nothing, and is clipped at rest. Two earlier placements were
  wrong: below the today anchor it landed a screenful past the pull on any
  timeline with a week ahead (which is why the quips were never seen), and as
  the scroll's first CONTENT it shoved the whole timeline down (Dave, build
  153). Because it lives in the gap it is visible only while the gap is open,
  and the system holds that open until the `refreshable` closure returns — so
  the closure waits a beat before returning, a connected sync says "Syncing…"
  BEFORE the network rather than after, and clearing hangs off the closure's
  tail (a fixed timer started at set-time expires mid-sync and empties an open
  gap). ⚠️ **The system refresh SPINNER is killed** — same gap, and two things
  in it is one too many. No hide API exists, so it is drawn in a clear tint
  (`.tint(.clear)` on the ScrollView, `.tint(Theme.textPrimary)` restoring the
  content's tint one level in). Today's is the app's only `.refreshable`.
  And **pull-to-refresh must not re-anchor the scroll**
  (`dayChangeToken` re-anchors, `dayToken` only re-derives): scrolling to today
  mid-gesture yanks the surface out from under the pull and carries its answer
  off-screen. A **pushed utility/catalog
  screen** with a fixed label keeps the small centered `pushedScreenChrome`
  title; a **pushed detail screen showing a dynamic name** clears its chrome
  title (`title: ""`) and leads the body with a large left header that wraps to
  two lines (`.lineLimit(2)` + `.fixedSize` + `.isHeader`) — Exercise / Equipment
  / Template / Routine detail. `SheetHeader` titles wrap to two lines. The record
  screen (`SessionDetailView`) is the deliberate exception: it keeps the centered
  title + mono subtitle, since routine names are short and the facts ride the
  subtitle slot.
- **Motion carries meaning, one mechanism each**: selection slides, data
  rolls, completion thuds (impact per set, `.success` only at the purple
  finish), navigation zooms. The tempo lives in `Theme.Anim` tokens, never
  inline curves (the "draw from Theme, never ad-hoc literals" law extended
  to motion): `.selection` (a snappy spring — front-loaded, no overshoot —
  for the scope wheel's tap-to-centre, selected fills/chips, schedule circles;
  an ease-out's decelerating tail made a sliding pill read muddy, 2026-07-12),
  `.standard` (~0.15 s ease-out for data rolls, opacity, search expansion),
  `.press` (0.06 s cap depression). Deliberate flourishes (splash fade,
  superset landing bloom, the green→purple completion beat) keep their own
  longer curves inline — they are exceptions to the fast-feel rule. The app
  always feels fast.
- **No obligation vocabulary** ("due" is banned) and **anti-shame**:
  regressions render neutral, diffs sum positive movement only, no
  out-of-band warnings.
- **No em dashes in user-facing copy** (Dave, 2026-07-10): rewrite the
  sentence (split it, or use "·" separators) instead. A bare "—" standing
  in for a missing value is a placeholder glyph, not prose, and stays.
- **The full brand voice lives in `.claude/skills/voice/SKILL.md`** (settled
  2026-07-17) — read it before writing ANY user-facing string, and run the
  `copy-reviewer` agent on diffs that touch copy. Headlines: no "we"/"I";
  the app never refers to itself except unavoidably, and then as
  "PlusPlus" (never "the app"); consequence before mechanism; "have
  access to" is retired (say "have" — OS-permission copy keeps "access");
  the term for a named equipment set is **"kit"**, default kit **`main`**.
- Warm charcoal dark (`#201F1D` family); the watch keeps system black.
- Draw every color from `Theme` — never ad-hoc literals.
- **Two tag tiers, rounded rects not pills, all-caps is section-labels-only**
  (2026-07-18, shapes/mono revised 2026-07-20): a **selectable chip** is a
  button — sentence-case plain font, a border when unselected, a solid blue
  fill when selected. `SelectableChip` is the last of them: the FACET chips
  (`FacetChip`/`MultiFacetChip`/`TrayFilterChip`/`FilterSummaryChip`/`SortChip`,
  and `KitFilterChip` before them) are **all DELETED as of 2026-07-25** — no
  catalog surface filters by facet any more, so nothing constructed them. If a
  facet is ever wanted again, git history has them; don't re-derive. A **card
  data tag** is not a button — it shows an item's property, so it wears the
  soft `surfaceRaised` fill with NO stroke (a stroked tag reads as a button).
  That style is the shared `CardTagCapsule` (the routine gear pills use it too).
  **Both tiers are ROUNDED RECTANGLES, not capsules** (2026-07-20): every
  interactive key in the app is a rounded rect, so the filter controls joined
  them at `FilterChipShape.cornerRadius` (11) and the data tags followed at a
  smaller r6 (a pill on a short tag; ~6 keeps the controls' corner-to-height
  proportion) — shape carries role by radius, control vs data, not pill vs
  rect. Data-tag text is sentence-case, standard (non-mono) caption (the mono
  was retired 2026-07-20). ALL-CAPS mono stays reserved for section labels.
  The property a filter/sort controls appears as a `CardTagCapsule` on the
  cards it narrows, so the two connect (muscle ↔ Muscle filter; category +
  "N exercises" ↔ Type filter / Most-exercises sort). One item reads the same
  everywhere via shared bodies — `ExerciseRowContent` (Exercises catalog +
  picker) and `EquipmentRowContent` (equipment catalog card + kit list),
  in `Views/Components/CatalogItemRow.swift` — with only parameterized
  exceptions (the picker drops the chevron; the kit list drops the in-kit
  glyph). See docs/DECISIONS.md 2026-07-18.
- **Design-review round laws (2026-07-23, Dave-decided):** (1) **No
  toasts, ever.** A transient answer renders INLINE where the triggering
  gesture settled (Today's pull-to-refresh line), or as a one-shot ALERT
  when it answers an explicit tap that would otherwise fail silently
  (renamed-routine deep links, unreadable share links). `Toast.swift` is
  deleted. (2) **Active filters summarize, never insta-clear**: the
  leading ✕ `ClearAllChip` died for `FilterSummaryChip` — a
  selection-blue count chip opening a popover naming each active facet's
  values (+ result count where cheap), Clear-all inside. ✕ now means
  ONLY collapse-search, everywhere. (3) **Interactive amber wears the
  control shape**: the routine header's tappable "needs X" chip is r11 +
  stroked; card data tags stay soft r6 and inert — no nested tap targets
  on cards, shape says what taps. (4) **The live-workout HUD is in the
  key family**: End/Pause/Overview are r11 raised keys (42 pt cap + 3 pt
  travel ≈ the old row height); HR/pace readouts are soft r6 data tags.
  (5) **One landing for every routine add/import**: the Routines list +
  entrance flash, via `RoutineArrival` (pending-uuid handoff + tab
  switch), from the Routines tab, Today's setup, and share imports alike;
  blank creation still lands in detail (creating starts editing). (6)
  **The superset creation tip teaches the DRAG**, as a popover pinned to
  the first rail row (reversing build-45's sheet-path-only copy; display
  gated by `SupersetCreationTip.canPair`). (7) The overview's "up next"
  pulse is a NAMED flourish (the 4th, beside splash/landing/completion).
  (8) **The exercise editor confirms a dirty discard** (blocked swipe +
  Cancel-confirm, the Mail-compose pattern) — the ONE exception to
  Cancel-is-instant, Dave's call. (9) **Ad-hoc sessions never
  auto-finish** (`stagedWorkDoneStage` offers Add/Finish); the record
  renders never-completed sets as neutral "skipped" rows (anti-shame:
  fact, not judgment). (10) `Theme.keyRadius` names the 11 pt key
  radius; `FilterChipShape.cornerRadius` aliases it. (11, round 2a)
  **The routine exercise sheet's structure actions are ALWAYS-VISIBLE
  compact pairs** ending in `Swap for…|Remove` — the round-1 Structure
  disclosure lived one build (Dave: hiding four small actions read as
  friction). The pair mirrors the live session sheet, so restructuring
  reads the same at planning and execution time; planning-time swap
  reuses `Routine.replaceExercise` (targets reset to the new
  exercise's defaults) via a `.swap` picker destination.
- **Equipment is availability, not ownership** (2026-07-11): what gear you
  "have" is membership in the ACTIVE `EquipmentLibrary` (Home, Hotel…),
  switched from a tray off the Equipment-tab header (left of the +) and via
  the catalog GEAR facet's "Switch library…" footer; the tab list re-renders
  behind the tray, which is how the app-wide scope reads. Lists never HIDE
  by kit availability (#113 flag-don't-hide, extended 2026-07-25): the
  Routines/Exercises tabs render the whole set doable-first, then group what
  the kit can't do under a collapsible "N … require more equipment" disclosure
  (see the search-UI section), with unavailable gear in notes amber ("needs X",
  card pills) on the rows inside. The
  **Exercises tab IS the whole catalog** (2026-07-17): an exercise is a
  thing you choose to do, not property, so there's no library — curation
  is FAVORITES (`Exercise.isFavorite`; `inLibrary` frozen). The old GEAR facet
  (four `GearMode`s: All / can do with the kit / can't / a hand-picked set) was
  the opt-in availability filter that replaced hide-by-default; it (and
  `GearPickSheet`) were RETIRED 2026-07-25 for the collapsible group, and later
  the same day **Favorites and Muscle went too** — no catalog surface carries
  facet chips now (the search field reaches what they reached), so the persisted
  `exerciseCatalog.*` keys died with them; curation is the MINE tier and the
  favorite swipe. Copy says "have"/"in your kit",
  never "own" (that word survives only for data ownership) and never "have access
  to" (retired 2026-07-17; permission-grant copy keeps "access" — Apple's
  word). **One possessive for the active kit: “your kit”** (2026-07-20;
  “My equipment”/“YOUR KIT ✓” retired as user-facing possessives — `GearFit.mine`’s
  raw value stays internal). **Naming the active kit follows one rule** (2026-07-20):
  a switcher CONTROL (the Kit-tab pill, the catalog “Adding to” strip, the routine
  Kit chip) always shows the raw kit name, since a control needs a label even with one
  kit; PROSE and verdicts use `EquipmentLibrary.activeNamePhrase` (name the kit once
  more than one exists, else “your kit”) so the rule lives in one place. Opening the
  catalog to change kit membership is always labeled **“Edit your kit…”**. The user-facing term is "kit",
  and the fourth tab is labeled **Kit** (2026-07-20); the word **"gear" is
  retired** from user-facing copy (2026-07-20) — use **kit** for the
  your-set sense, **equipment** for the single-item / catalog sense
  ("Equipment catalog" keeps its name). `EquipmentLibrary` the type, the
  `AppTab.equipment` case, and the interchange's
  `program/equipment-libraries/` path are frozen internals.

## What the app is, surface by surface

**What works (as of 2026-07-07 late-night, design-v3 end to end):** the Claude Design v3 handoff shipped in one overnight arc — #114 palette, #115 nav, #124 Today+diffs, #125 schedule+onboarding, #126 watch v1, plus the #107 scroll root-cause fix and #127 gesture hardening. The app is four bottom tabs on the native iOS 26 Liquid Glass TabView (#130): Today · Routines · Exercises · Equipment. **Today** — the unified timeline: pending (due) workouts as dashed cards with per-exercise diff summaries (`+5 lb · +2 reps · 1 new · 2 =`), expandable rows, due captions ("due today" / "due since thu"), full-width Start; committed sessions below with net chips (green, up-only); rest-day/first-run timeline items and a swap-in sheet for off-schedule sessions; settings opens here. **Routines** — cards with schedule + equipment pills, header + creates; detail keeps the v2 rail (+ a share button, #145) (drag/ring gestures now on a UIKit recognizer so the list actually scrolls) with schedule/rest chips under the title. **Exercises / Equipment** — pushed detail screens forming a navigable graph (#137: equipment ⇢ exercises ⇢ routines, create-at-every-dead-end); the header + pushes CatalogBrowseScreen (#139: whole catalog listed, membership toggles, All/In-library/Not filters); built-ins editable except name, with revert-to-default (#136). **Sharing** — routine detail → `plusplus.fit/r#…` link (payload in the fragment, never on a server); `plusplus://` links open an import preview (#145). **Onboarding** — setup-as-timeline (#132): no cover screen; a fresh install's Today shows three setup steps as gated timeline entries (equipment → first workout → schedule, bottom-up like commits) that become committed-style cards when done and yield to real history at the first logged session; equipment access re-runnable from Settings → EQUIPMENT ACCESS. **Watch** — WatchConnectivity companion: plan pushed on launch/backgrounding, wrist execution (frozen step list, log/rest/haptics, watch-local rest-over notification, early exit), finished sessions sync back as append-only history with a synchronous acked import. Session records show block-level Δ vs the previous same-workout session. **Platform surfaces (#147, build 17; whole-session in #322)** — a Live Activity spanning the workout (Dynamic Island + Lock Screen): `.working` (exercise · set N/M · count-up elapsed) swapping to `.resting` (countdown + +30s/Skip), driven from ActiveSessionView's lifecycle via `WorkoutActivityController`. #322 also REMOVED the phone rest/timer local notifications (and their permission prompt) — the rest-over cue is watch haptics + the island countdown, not a phone banner; *Due today* and *Streak* widgets (12-week mini contribution row) reading a `WidgetSnapshot` written to the App Group (`group.com.davidcole.plusplus`) on launch/backgrounding; App Intents (StartRoutineIntent / DueTodayIntent / OpenTodayIntent + shortcut phrases — intents read the snapshot, StartRoutine posts `.plusplusStartRoutine` and RootTabView/TodayView react). **Design v4 (2026-07-08, overnight)** — blue selection grammar everywhere (`selected`/`selectedTint`/`selectedRing`; segmented tabs lost their ink fill; one motion rule: 0.15 s ease-out + selection haptics); routine settings and app settings are pushed pages (routine settings = NAME/rename tray/SCHEDULE/rest/notes tray/Delete-with-confirmation; detail header shows plain facts); the Today pending card is name+estimate / Configure capsule / muscles+gear rows / promoted diff; the superset rail redrawn (solid spine, border-colored return loop with chevrons at rest, selection-blue highlight + SUPERSET legend only while the ring gesture is live; SUPER swipe died); onboarding equipment rides the real catalog in setupMode (pinned Done bar; the preset strip died as destructive, #203); TipKit replaced the ambient captions; fresh installs seed the catalog with an EMPTY library (#185). **Build-27 feedback round (2026-07-08 morning)** — completion is PURPLE (#201: `Theme.done`, GitHub's merged pair — committed rail nodes, session pips, the finished checkmark, widget streak squares; green stays data-in-motion, blue stays selection); creation affordances are GREEN everywhere (#202); the populate offer asks from a centered alert on Today with an ask-time count (#204 — the catalog popover floated anchored to nothing); the catalog is EXTENSIVE (#95 content: 157 exercises / 40 equipment, and `loadIfNeeded` is a name-matched top-up so growth reaches existing stores — newcomers arrive catalog-only and un-owned, curation untouched). **Build-28/29 feedback round (2026-07-08 afternoon)** — routine settings: no Save at all (#219 killed it hours after #207 added one — every field commits live, the name on any exit, so the page is simply always saved), Delete nests in an upper-right `…` menu, name/notes edit INLINE (trays deleted; commits also fire in `onDisappear` because swipe-back bypasses `onBack`); the swap-in sheet only opens when a startable routine exists and both empty paths offer creation (which pushes straight into the new routine); tabs are capitalized; selected states are SOLID blue everywhere; **catalog search is an in-header expanding field** (build-42 `pushedScreenChrome` + `HeaderSearchConfig`, superseding the build-28 floating-dock pattern and #233's toolbar button: a magnifier key expands into a field replacing the title, inline ✕ collapses it), with scroll-to-dismiss on every list under a search field; **the polish batch** (#216): the segmented-tab pill SLIDES between segments, digits ROLL on step (directional on the set screen), set-logging is an impact thud with `.success` reserved for the purple finish, and cards ZOOM into their screens (routine card → detail, pending card → live workout, committed card → record; off-card starts fall back to the standard transition); **the Today rail speaks the grammar**: green ring = ready to do, grey ring = rest day, fainter ring = gated setup step, purple dot = done; and any session that misses Finish/Discard (crash, or a dismissal path the exit dialog never saw) is salvaged on Today's next appearance instead of becoming an invisible orphan. **Equipment catalog rebuild (2026-07-17)** — the equipment kind left `CatalogBrowseScreen` (now exercises-only): `EquipmentCatalogScreen` lists cards you tap INTO (detail push via an item destination on the browse itself, #291-legal from every call-site class) with a leading swipe-right quick-add (green ADD ↔ destructive REMOVE by membership; the screen declares `.leadingRevealHost` so back-swipe narrows to the edge band), a quiet mono "N exercises" capsule per row fed by one per-render index pass, and filters: KIT facet (In kit/Not), MUSCLE tray over the same index. `EquipmentDetailScreen` leads with **Add to kit** and a CONFIGURE section of sheet-per-value rows. The user-facing term is **kit** everywhere on equipment surfaces; the default kit is **`main`** (`EquipmentLibrary.defaultName` + the lone-untouched-"Home" one-shot). **Build-94 feedback round (2026-07-17):** the filter row is now ONE mono chip vocabulary — KIT facet · TYPE tray (`EquipmentTypeFilterSheet`, multi-select over `SeedData.equipmentCategories`, replacing the inline chips that read as uneven spacing) · MUSCLE tray · a neutral `SortChip` (Name / Most exercises — the exercise count is sortable, not just a capsule). The "N exercises" capsule moved into the row's LEFT column (next to the name), and in-kit is a right-side accent `checkmark.circle.fill` glyph (the "in kit ✓" words dropped). The type category "Bodyweight anchors" → **"Bodyweight gear"**. On the detail, **Add to kit is a prominent toggle card** (flip on/off, removal no longer in the … menu — that menu is custom-delete only; the WHOLE card is the tap target — the toggle stays the identified interactive switch and an `.onTapGesture` on the card flips the SAME membership binding from anywhere else on it, so a tap is one flip whichever gesture wins); the exercises/routines cross-links + "New exercise/routine with…" are **hidden during setup** (`isOnboarding`) so onboarding stays on the add-and-configure task; the **"Tracks" metric config is gone** (`EquipmentMetricsSheet` deleted — metrics belong to the exercise, not the gear; the `metricsData` field stays for load/export), so CONFIGURE shows only "Weight step" and only for loadable gear. The onboarding **setup scaffold pins step 1 (equipment) at the top** of the scroll on first open, with headroom capped to a viewport minus the measured step height so it can't be scrolled off the top.
