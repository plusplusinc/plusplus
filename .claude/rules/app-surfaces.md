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
  (2026-07-18; universal search 2026-07-23): cross-type search lives on the
  **Find-or-create surface** behind the tab bar's search item
  (`Tab(role: .search)` → `FindOrCreateView`) — the tab-root headers carry NO
  magnifier anymore. On that surface the field is the NATIVE `.searchable`
  (2026-07-24, Dave — superseding the custom bottom-bar takeover): placed
  INSIDE the search tab's stack (placement B) so its prompt can read the scope,
  the search-role tab morphs the tab bar into the system field at the bottom,
  carrying the native clear (✕) and Cancel. The placeholder is per-scope
  ("Search" on All, "Search routines/exercises/equipment" when scoped) and it
  does NOT auto-focus on entry — no `.tabViewSearchActivation(.searchTabSelection)`,
  so the keyboard rises only on a field tap (`.searchFocused` is used solely for
  the "type a name first" refocus). There is NO custom Done key now: leaving is a
  normal tab tap. ⚠️ This re-arms the documented iOS 26 morph bug — an
  `.onGeometryChange` in the TabView subtree (TodayView's onboarding step-height
  probe) can make the field render as a top bar on the FIRST activation instead
  of morphing (nav-diag 4e); device-pass on the shipping OS, and if it recurs,
  rework that probe. `SearchFieldBody` stays — the pushed catalogs/pickers/sheets
  still use it via `HeaderSearchField`. Scope +
  Doable stay the top controls. Pushed catalogs, pickers, and sheets keep the expanding
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
  **Add** (`Add <object>` / `Add "<query>"`) when it navigates — the tabs' Add
  rows now open Find-or-create pre-scoped (`FindOrCreateLaunch`), as does
  onboarding step 2 ("Pick a routine" → `.open(.routines)`; the standalone
  `RoutineCatalogScreen` was retired here, 2026-07-24). Query casing
  is `String.sentenceCasedFirst`. Empty results NEVER dead-end: the create/add
  row is always present + a "Clear filters" `QuietKey` when facets are active.
  The ONE thing that removes a create is an EXACT-name collision (2026-07-24):
  when the trimmed query case-insensitively equals an existing item's name,
  that type's create is suppressed (Find-or-create; `FindOrCreateEngine.Collisions`)
  so the surface never offers to duplicate the row sitting right below it —
  never a dead end, because an exact match always ranks into results, so
  results are non-empty whenever a create is hidden. Partial matches still
  offer create.
  **Scope is an inline horizontal WHEEL** (`InlineWheelPicker`, 2026-07-24 —
  replaced the earlier content-width `SegmentedTabs`), above the field: a FIXED
  selection band the scopes wheel through (native-picker idiom), pinned LEFT so
  its leading edge sits on the 16 pt content column (lines up with the field +
  rows) and sized INTRINSICALLY to the widest option label + even padding +
  reserved chevron/gap space (a hidden width-probe `PreferenceKey`, not a
  fraction of the track). White selected / grey unselected (no blue — selection
  reads by the band + weight, not a pill); a soft 3D cylinder tilt on the
  wheeling options (per-cell `.visualEffect`, Reduce Motion flattens it). Faint
  chevrons sit INSIDE the band on either side AS NEEDED (the band is at the edge,
  so nothing peeks left — the chevron is the "more that way" cue); tapping one
  steps that way, and they fade while the wheel is in motion. Change it by
  dragging, tapping an option, or tapping a chevron; icons on the typed scopes,
  "All" text-only. It leads the field because scope is a MODE (changes the create
  verb + what an empty query browses), not just a filter. Native scroll mechanics
  (`ScrollView(.horizontal)` + `.viewAligned` + `.scrollPosition(id:)` +
  asymmetric `contentMargins` for the left-anchored snap), so it can never
  overflow the viewport the way the old segmented track could. NOT the native
  `Tab(role:.search)` bottom-morph (the app owns its selection grammar; a sibling
  tab's `.onGeometryChange` triggers the documented iOS 26 morph bug).
  **A11y (segmented-control model):** each option is a labelled `Button` with the
  `.isSelected` trait (VoiceOver "Exercises, selected, button"; Voice Control by
  name; the 44 pt row is the target); decorative icons + the supplementary
  chevrons are hidden from assistive tech; VoiceOver's reveal-scroll is guarded
  from mutating the selection (only a tap/drag changes it) via the
  `accessibilityVoiceOverEnabled` gate on the scroll→selection sync. The custom
  `SegmentedTabs` was RETIRED (2026-07-24) — every other former segmented site
  moved to native `Picker` (`.segmented` for short unit/mode toggles, a pushed
  `NavigationSelectRow` for multi-word modes).
  **The "Doable" filter** (persisted `@AppStorage`, default on) hides
  routines/exercises the active kit can't do (All/Routines/Exercises; Kit is
  equipment, unfiltered) — a single chip by the scope (the persistent two-way
  control, so the trip back is the same tap; a bottom reveal footer was
  rejected for burying the return). An EXACT-name match always surfaces past
  the filter (search intent + the create-collision guard); off reveals all with
  per-row amber "needs X"; when the filter alone empties results, the state
  offers a "Show all" `QuietKey`, never a bare "Nothing matches." Copy is
  **"Doable"** — names the item-set, equipment-agnostic (a bodyweight move is
  doable, not "equipped"), no collision with the adjacent "Kit" segment.
  Results use real `List` `Section`s so `.listStyle(.plain)` PINS each heading
  to the top until the next takes over (one sticky at a time); the header wears
  a solid `Theme.background` so a pinned heading occludes the rows beneath it.
  Search state on the universal surface is EPHEMERAL per-entry (a stale
  invisible query reads as data loss); every add from it LANDS on its list
  with the entrance flash (`RoutineArrival`/`ExerciseArrival`/
  `EquipmentArrival` + `RowEntranceFlash` — one landing for every add).
- **Heading treatment follows the nature of the title** (2026-07-18, updated
  2026-07-19): a **tab root** wears a large left `.title` heading ON the icon
  row, just right of the ++ key (`AppMenuKey`) — single-line, `.layoutPriority(1)`
  so it claims its space first and all four roots (Today · Routines · Exercises ·
  Equipment) read at one font size; any squeeze from a trailing accessory (the
  Equipment kit switcher) falls on THAT key (its own `minimumScaleFactor`), never
  ejecting a fixed key off the row. **Do NOT use `.fixedSize` here** — a fixed
  Dynamic-Type title shoves the trailing search/switcher keys off-screen at large
  text sizes (swift-reviewer/axiom catch). **At `dynamicTypeSize.isAccessibilitySize`
  the heading reflows to its own line BELOW the icon row** (`.lineLimit(2)` +
  `.fixedSize(vertical:)`, wraps at full size), the canonical "reflow, don't cap"
  fix (#164), so every icon-row key stays reachable. The title hides while the
  header's expanding search field is open. Shared: `CatalogTabHeader`
  (Routines/Exercises/Equipment); Today has a hand-rolled twin. A **pushed
  utility/catalog
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
  (2026-07-18, shapes/mono revised 2026-07-20): a **filter chip** is a button
  — sentence-case plain font, a border when unselected, a solid blue fill when
  selected (`FacetChip`/`MultiFacetChip`/`TrayFilterChip`/`SortChip`/
  `SelectableChip`, facet names passed sentence-case; the old
  `KitFilterChip` sheet-chip retired with the 2026-07-21 axes separation —
  the equipment catalog's Kit facet is a plain `FacetChip`). A **card
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
  behind the tray, which is how the app-wide scope reads. Lists
  flag-don't-hide (#113): the Routines/Exercises tabs render unavailable
  gear in notes amber ("needs X", card pills) rather than hiding it. The
  **Exercises tab IS the whole catalog** (2026-07-17): an exercise is a
  thing you choose to do, not property, so there's no library — curation
  is FAVORITES (`Exercise.isFavorite`; `inLibrary` frozen), and the GEAR
  facet's four modes (All / can do with the kit / can't / a hand-picked
  set) are the opt-in availability filter that replaced the old
  hide-by-default. Filters persist device-locally. Copy says "have"/"in your kit",
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
