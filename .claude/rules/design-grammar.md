---
paths:
  - "PlusPlus/Views/**"
  - "PlusPlus/Theme/**"
  - "PlusPlusWatch/**"
  - "PlusPlusWidgets/**"
  - "PlusPlusShared/**"
---

# Design grammar (color · keys · tags · motion · copy)

Current since the Quiet Arcade refresh (reasoning: docs/DECISIONS.md,
2026-07-07 → 2026-07-10 entries, plus the dated entry each law cites).
Siblings: `navigation.md` (tab bar, search, scope control, landings),
`today-rail.md` (Today's band, rail, landmarks, pull),
`app-surfaces.md` (what each screen is), `ui-interaction.md` (gesture laws).

- **Green is data/creation** (deltas, net chips, the ++ glyph, create
  affordances, the Start play key) — never chrome.
- **Blue (#1668D2/#5CA8F5) is selection state, never decoration** — ONE look
  (tinted ground + ring + `selectedInk` label), worn by every currently
  selected control, however many share the screen (the facet row's active
  chips + summary chip are the precedent, 2026-07-31); outside selection,
  blue appears only in the live ring gesture. ⚠️ Solid blue fills are
  RETIRED (2026-07-28, Dave, reversing #210): chips, the increment sheet and
  the schedule day circles select the way selectable ROWS do — one selection
  look. ⚠️ A selected LABEL takes `Theme.selectedInk`, NOT `selected` — plain
  blue measures 4.07:1 on its own 12% wash over `surface`, under the AA floor
  for footnote-sized labels (2026-07-28). **A hue proven on a solid fill has
  not been shown to read on a wash of itself.** `Theme.onSelected` survives
  only where something genuinely sits on a solid fill; `Theme.selected` is
  retired as a text/link color; escape hatches are quiet keys. On the superset
  rail (design handoff 2026-07-12 v2), blue is the MOMENT OF CREATING: the
  live ring highlight and the landing animation (reshape + snap, pulse spark).
  The SETTLED superset return-loop rests in `Theme.supersetLoop`, an OPAQUE
  warm gray (`#7C786F`) a step above the neutral spine — a bound block is
  structure, not selection. (Translucent resting blue composited with itself
  at Canvas stroke overlaps and read blotchy; opaque ink strokes uniformly.)
- **Purple is done** (GitHub-merged mapping): the committed Today rail node —
  a FILLED purple checkmark circle (2026-07-24; the seal lives on the rail
  dot, NOT the committed card; every OTHER timeline node stays a stroke-only
  ring, all nodes one 18 pt diameter) — session pips, the finish checkmark,
  widget streak squares. The live set bar joins them (2026-07-28): blocks are
  done purple · live green · upcoming inert, and the live block BREATHES while
  a rest countdown runs (the cursor has advanced, so that block IS the up-next
  set). ⚠️ Status is per LOG, never `index < filled` — a jump completes sets
  out of order. A DONE block is a correction DOOR (#504, Q8-B): its tap
  PRESENTS the set's values with an explicit confirm in the block's own
  noun ("Correct piece 2?"), and only that confirm moves the cursor —
  never the tap itself. VoiceOver keeps the bar as one summary element;
  the overview's Redo is the accessible correction route.
- **Amber (`Theme.notes`) is advisory, never alarm** — neither green
  (do/create) nor grey (inert). Two jobs: form-cue / "needs X gear" notes, AND
  a **carried-over occurrence** (2026-07-14) — a scheduled day lapsed within
  the 6-day window shows in Today's carried-over lane (below today's cards,
  above history) as an amber tap-to-open card under a plain past-dated rail
  row ("wed · jul 22"; the "was" prefix retired 2026-08-01, the amber and
  the position carrying the tense), never a green due. The lane is UNLABELED (2026-07-23 round 2b: the rail's all-caps
  headings died; date line, cadence lines, and the cards' border/node/
  caption-tense grammar carry the structure). Green + one-click Start is
  reserved for TODAY's occurrence only; future and carried cards navigate to
  detail. Due-ness anchors to `Routine.scheduleAnchor` — the LATER of
  `createdAt` and the last schedule change (`scheduleChangedAt`) — so a fresh
  routine never carries a day it wasn't around for, and a freshly SET schedule
  never banks tomorrow against a completion that predates it. Kit split:
  `DueState.due` = scheduled today and unmet; `.missed(since:)` = lapsed.
- **RaisedKey press grammar**: every committing/navigating button is an opaque
  cap depressing onto a fixed base plate (4 pt standard / 3 pt quiet, 0.06 s
  ease-out); flat controls (chips, toggles, segments, rows) stay flat.
  ⚠️ **The app's chrome stops at the navigation bar** (Dave, 2026-08-02,
  reversing the build-42 call for the TOOLBAR only): a key in a system
  `ToolbarItem` is NATIVE — a bare `Image` label, no frame, no ground, no
  `.raisedKey()` — and the bar plates, sizes, tints and presses it.
  `pushedScreenChrome` AND `sheetChrome` are the system bar now, so no
  hand-drawn header band survives anywhere. `HeaderKeyChrome` is the switch:
  `HeaderIconButton`/`HeaderMenuKey`/`LibrarySwitcherKey` take `.toolbar` in a
  bar, `.raised` everywhere else; `AppMenuKey` is toolbar-only with no raised
  variant. Its glyph keeps brand GREEN — the mark, not chrome.
  ⚠️ **Tint is OPTIONAL and `nil` is the default on purpose**: a toolbar
  control takes the BAR's tint unless the app means something by its colour
  (the lit favourite star goes `Theme.accent` — the user's own data).
  ⚠️ `.sharedBackgroundVisibility(.hidden)` came OFF every toolbar key with the
  app-drawn ground: it stopped a raised cap nesting inside the toolbar's shared
  glass (a box in a box), and a bare glyph WANTS that glass.
  **Icon-only keys are 11-pt ROUNDED SQUARES
  everywhere the app still draws them** (2026-07-19; the all-circles round and
  the sheet-corner concentric experiment were both reverted by Dave — uneven
  concentric corners read wrong): `HeaderIconButton`/`HeaderMenuKey` in sheets
  and trays, plus Operator
  send-stop, use `RoundedRectangle(cornerRadius: 11)` + `.raisedKey()`. The one
  sanctioned variant is `ConfigIconButton` (30 pt cap, r8, FLAT bordered — it
  configures a value in place, it doesn't commit or navigate; the radius
  scales with the cap). No other per-context corner variation.
  ⚠️ **The hand-built glass exception is GONE, and its RULE outlived it**
  (Dave, build 176). `CatalogSearchDock` — a Liquid Glass circle morphing into
  a capsule, floating above the tab bar — is deleted; search is a native item
  in the top toolbar, so the app draws no glass at all any more. What the
  exception was FOR still binds and is now the general law: **a control wears
  what it SITS AGAINST.** In a system bar that means native, bare, and the
  bar's own glass (the toolbar law above). In app-drawn chrome — sheets, trays,
  the picker's field — it means the r11 opaque cap. Asking "what is this NEXT
  TO" is the question; the dock was one answer to it, and a short-lived one. ⚠️ **A raised
  key's cap and its hit target are ONE rectangle** (build 161): `RaisedKeyStyle`
  plates the frame it is GIVEN, so a smaller cap inside a bigger hit frame draws
  the plate as a second box around it. Grow the frame, not the gap. Every "New …" / "Add …" /
  "Create …" list row is the shared `CreateRow` (a green bordered raised key),
  so creation reads as a button, not floating text. Keys that carry TEXT keep
  the rounded-rect pill: `QuietKey`, `LibrarySwitcherKey`,
  the primary action bars.
  ⚠️ **A key that ENDS the workout in one gesture SLIDES** (Q4, 2026-08-01):
  the single-effort commit key ("Finish workout" in the log and timer docks)
  is `SlideToFinishKey` — the cap slides the length of its own base plate
  (worn full-width as the track) and commits at the end of travel; a tap
  only wiggles it, which is the affordance teaching the slide. VoiceOver /
  Switch Control / Voice Control activate it DIRECTLY
  (`accessibilityRepresentation` Button, same `completeSetButton`
  identifier) and Return still finishes (hidden keyboard-shortcut sibling)
  — but XCUITest does NOT ride that representation: `tap()` is a
  synthesized TOUCH, not an activation, so under `--uitest-reset` a tap
  commits (test-only door, StartFlashButton's precedent). The exit
  dialog's Finish stays a TAP — it already sits behind a confirm. The
  slide itself is XCUITest-invisible: device pass. Drag transients are
  `@GestureState` (a cancelled touch must spring the cap home, never
  strand it — ui-interaction.md's latch law extended).
  ⚠️ **A screen that completes on its own has NO primary key** (2026-07-27,
  Dave, from the rest screen): a filled `primaryFill` cap is the commit
  grammar, so putting one on a screen whose job is to finish by itself makes
  the escape read as the thing to do. The rest screen's only filled keys
  ADJUST the countdown; Skip is a quiet cap, set apart by an extra gap so a
  thumb stepping `−15s` twice can't end the rest. Where an escape shares a row
  with keys you tap repeatedly, give every key the SAME travel (`.raisedKey`
  beside `.raisedPrimaryKey`, not `.quietKey`'s 3 pt) so caps sit on one
  baseline; carry the quiet reading in fill, ink and type instead.
- **Sheet dismissal and ✕**: ✕ means ONLY "collapse search", everywhere. A
  sheet/tray NEVER dismisses with a ✕ — it dismisses with a WORD ("Cancel" to
  abandon edits or to leave a picker without picking, "Done" view-only). ⚠️
  That law SURVIVED the native conversion; the control under it did not
  (2026-08-02). **A sheet wears the SYSTEM navigation bar** via `sheetChrome`
  — the same bar as a pushed screen: inline title, optional
  `.navigationSubtitle`, Cancel LEADING (`.cancellationAction`), commit
  TRAILING (`.confirmationAction`). `SheetHeader`/`SheetDismissKey` are
  DELETED. Two visible changes, both chosen: Cancel moved left from beside the
  commit, and the commit lost its green `primaryFill` capsule (the capsule
  said "committing is an ACTION"; the bar says it with position and weight).
  ⚠️ The HOST owns the `NavigationStack` and presentation modifiers stay
  outside it (`ui-interaction.md`) — a `.navigationTitle` with no bar to land
  in renders nothing, silently. ⚠️ No header can carry a `.keyboardGround` any
  more; `SheetComponents.swift` and `KeyboardGround.swift` carry the rest.
  Search-field anatomy and the create/add verbs: `navigation.md`.
- **Pushed-screen titles follow the nature of the title** (2026-07-18): a
  **pushed utility/catalog screen** with a fixed label keeps the small
  centered `pushedScreenChrome` title; a **pushed detail screen showing a
  dynamic name** clears its chrome title (`title: ""`) and leads the body with
  a large left header wrapping to two lines (`.lineLimit(2)` + `.fixedSize` +
  `.isHeader`) — Exercise / Equipment / Template / Routine detail.
  A SHEET's title is the system bar's, so it does not wrap — where a sheet
  needs a second line it takes a subtitle. The record screen
  (`SessionDetailView`) is the deliberate exception: centered title + mono
  subtitle, since routine names are short and the facts ride the subtitle.
  Tab-root chrome (system large-title bar) is `navigation.md`'s.
- **One swipe law on every catalog row: LEADING is curation, TRAILING is
  destructive** (2026-07-25). ⚠️ Swipe-block fills come from the
  `Theme.swipeAdd`/`swipeDelete`/`swipeNeutral` family, never from
  `accent`/`destructive`: the system draws a swipe title WHITE whatever the
  tint, so the fill is chosen for white and is FIXED in both schemes (white on
  dark-scheme green measured 1.97:1 before this, 2026-07-28). REMOVE takes
  `swipeNeutral`, like UNFAV — it drops a piece from the active kit and the
  same swipe puts it back; DELETE ends the object everywhere. Exercises lead
  FAV/UNFAV, trail DELETE on customs only; Kit leads ADD/REMOVE membership,
  trails DELETE on customs; Routines trail DELETE. Catalog templates have
  neither. **Row context menus are gone** — the swipes ARE those acts, and on
  Routines a long press belongs to `.onMove`. **Reorder is routines-only,
  tab-only, empty-query-only, MINE-tier-only**: a ranked or narrowed list has
  no order to write back. Routines render as **cardless rows** outside Today —
  a catalog list reads flat — but cardless is a CHROME decision: the row still
  renders the shared `RoutineCardContent` (title · `focus · schedule · effort
  · estimate` · equipment tier). Templates render the same body from
  `RoutineMeta(focus:effort:estimate:gear:)`, so a template reads identically
  to the routine it becomes.
- **Motion carries meaning, one mechanism each**: selection slides, data
  rolls, completion thuds (impact per set, `.success` only at the purple
  finish), navigation zooms — and an OFFER morphs in place (the anytime
  card, 2026-08-01: a tapped key's CHROME grows into its config panel via
  `matchedGeometryEffect` on `Theme.Anim.selection`, content fading; never
  match content views — text reflows mid-flight — and never a measured
  FLIP, which writes layout state where the morph law forbids it).
  ⚠️ **A GLASS morph is the system's, not that recipe** (2026-08-02): the
  search dock pairs a `GlassEffectContainer` with a shared `glassEffectID`,
  which is the mechanism the search-role tab used to expand out of the bar.
  `matchedGeometryEffect` cannot fluidly reshape glass, and running both makes
  them fight over the same geometry. The rule follows the MATERIAL: app-drawn
  chrome morphs with `matchedGeometryEffect`, glass morphs with
  `glassEffectID`, and neither borrows the other's mechanism. Tempo
  lives in `Theme.Anim` tokens, never inline
  curves: `.selection` (snappy spring, front-loaded, no overshoot — an
  ease-out's decelerating tail made a sliding pill read muddy, 2026-07-12),
  `.standard` (~0.15 s ease-out for data rolls, opacity, search expansion),
  `.press` (0.06 s cap depression). Deliberate flourishes (splash fade,
  superset landing bloom, the green→purple completion beat, the overview's
  "up next" pulse) keep their own longer curves inline — named exceptions to
  the fast-feel rule. The app always feels fast.
- **No obligation vocabulary** ("due" is banned) and **anti-shame**:
  regressions render neutral, diffs sum positive movement only, no
  out-of-band warnings. ⚠️ Scoped, not repealed, by the ledger movement inks
  (2026-07-30): a TARGET printed beside the prev it differs from wears
  direction — `Theme.increaseInk` green / `Theme.decreaseInk` gentle brick
  (Dave: "decrease is not a problem") — marking the PLAN's movement against
  the performance, never the performance itself, never a bare signed number.
- **No em dashes in user-facing copy** (Dave, 2026-07-10): rewrite the
  sentence (split it, or use "·" separators). A bare "—" standing in for a
  missing value is a placeholder glyph, not prose, and stays.
- **Type is the system ramp, worn plainly** (Dave, 2026-07-31 — a law, not
  tokens): dynamic text styles only (`.font(.system(.footnote, ...))`), so
  Dynamic Type reflow comes free. Fixed sizes are reserved for DISPLAY
  NUMERALS (the live metric value, the splash mark and their kin — the few
  sanctioned sites that exist today). Mono (`design: .monospaced`) is DATA:
  numerals, lowercase metadata captions, and the all-caps section labels
  above. Weight carries emphasis (semibold on keys and labels), never a
  second face. There is deliberately NO Theme type-token layer — the system
  styles are the ramp, and abstraction waits for real duplication pain.
- **The full brand voice lives in `.claude/skills/voice/SKILL.md`** — read it
  before writing ANY user-facing string, and run the `copy-reviewer` agent on
  diffs that touch copy. Headlines: no "we"/"I"; the app never refers to
  itself except unavoidably, and then as "PlusPlus" (never "the app");
  consequence before mechanism; "have access to" is retired (say "have" —
  OS-permission copy keeps "access"); the term for a named equipment set is
  **"kit"**, default kit **`main`**.
- Warm charcoal dark (`#201F1D` family); the watch keeps system black.
- Draw every color from `Theme` — never ad-hoc literals. ⚠️ The five brand
  HUES live in `BrandPalette` (PlusPlusShared, compiled into the app AND the
  widget extension) and `Theme` reads them from there (2026-07-28); neutrals
  stay in `Theme`, since widgets draw on the system's ground. The widget
  extension has NO palette of its own — its private copy lacked the
  high-contrast variants, so widgets ignored Increase Contrast while it
  existed. `WatchTheme` is the one legitimate second palette: watchOS renders
  only the dark side, and that target doesn't compile PlusPlusShared.
- **Two tag tiers, rounded rects not pills, all-caps is section-labels-only**
  (2026-07-18, shapes/mono revised 2026-07-20): a **selectable chip** is a
  button — sentence-case plain font, border unselected, tinted ground + ring
  selected (`SelectableChip`'s anatomy). **Facet filtering RETURNED
  2026-07-31** (Dave, reversing the 2026-07-25 retirement) as `FacetChip` +
  `FilterSummaryChip` (`Views/Components/FilterChips.swift`), REBUILT on that
  anatomy — ⚠️ the git-history versions wear the retired solid-blue fill; do
  not copy them. **A facet with a real list of options is a TRAY**
  (`FacetTrayChip` → `SheetPickList`, multi-select, #498); a BINARY facet
  (mechanic, sides) keeps its single-select `FacetChip` Menu, because picking
  both options says what picking neither says. Never a multi-select `Menu`
  (ui-interaction.md). A chip states its own selection the way the row's
  summary states the row's: the value when there is one, `name · N` when
  there are several. The summarize-never-insta-clear law below has its live
  consumer again. `MultiFacetChip`/`TrayFilterChip`/`SortChip`/
  `KitFilterChip` stay deleted — no sort, no kit facet. A **card data tag** is not a button — it
  shows a property, so it wears the soft `surfaceRaised` fill with NO stroke
  (a stroked tag reads as a button). That style is the shared
  `CardTagCapsule` (routine gear pills too). **Both tiers are ROUNDED
  RECTANGLES, not capsules** (2026-07-20): every interactive key is a rounded
  rect, so filter controls sit at `FilterChipShape.cornerRadius` (11) and data
  tags at r6 — shape carries role by radius, control vs data. (The search
  dock's glass capsule is the one exception, scoped by neighbour — see the
  icon-key law above.) Data-tag text is
  sentence-case, standard (non-mono) caption. ALL-CAPS mono stays reserved for
  section labels. The property a filter/sort controls appears as a
  `CardTagCapsule` on the cards it narrows, so the two connect. One item reads
  the same everywhere via shared bodies — `ExerciseRowContent` (catalog +
  picker) and `EquipmentRowContent` (catalog card + kit list), in
  `Views/Components/CatalogItemRow.swift` — with only parameterized exceptions
  (picker drops the chevron; kit list drops the in-kit glyph). See
  docs/DECISIONS.md 2026-07-18.
- **Design-review round laws (2026-07-23, Dave-decided):** (1) **No toasts,
  ever.** A transient answer renders INLINE where the triggering gesture
  settled (Today's pull-to-refresh line), or as a one-shot ALERT when it
  answers an explicit tap that would otherwise fail silently (renamed-routine
  deep links, unreadable share links). `Toast.swift` is deleted. (2) **Active
  filters summarize, never insta-clear**: `FilterSummaryChip` — a
  selection-blue count chip opening a popover naming each active facet's
  values, Clear-all inside. (3) **Interactive amber wears the control shape**:
  the routine header's tappable "needs X" chip is r11 + stroked; card data
  tags stay soft r6 and inert — no nested tap targets on cards, shape says
  what taps. (4) **The live-workout HUD is in the key family**:
  End/Pause/Overview are r11 raised keys (42 pt cap + 3 pt travel); HR/pace
  readouts are soft r6 data tags. (5) **One landing for every routine
  add/import**: the Routines list + entrance flash (mechanics in
  `navigation.md`); blank creation still lands in detail (creating starts
  editing). (6) **The superset creation tip teaches the DRAG**, as a popover
  pinned to the first rail row (gated by `SupersetCreationTip.canPair`). (7)
  The overview's "up next" pulse is a NAMED flourish. (8) **The exercise
  editor confirms a dirty discard** (blocked swipe + Cancel-confirm, the
  Mail-compose pattern) — the ONE exception to Cancel-is-instant, Dave's
  call. (9) **Ad-hoc sessions never auto-finish** (`stagedWorkDoneStage`
  offers Add/Finish); the record renders never-completed sets as neutral
  "skipped" rows (anti-shame: fact, not judgment). (10) `Theme.keyRadius`
  names the 11 pt key radius; `FilterChipShape.cornerRadius` aliases it.
  (11, round 2a) **The routine exercise sheet's structure actions are
  ALWAYS-VISIBLE compact pairs** ending in `Swap for…|Remove` (Dave: hiding
  four small actions read as friction). The pair mirrors the live session
  sheet, so restructuring reads the same at planning and execution time;
  planning-time swap reuses `Routine.replaceExercise` (targets reset to the
  new exercise's defaults) via a `.swap` picker destination.
- **Equipment is availability, not ownership** (2026-07-11): what gear you
  "have" is membership in the ACTIVE `EquipmentLibrary` (Home, Hotel…),
  switched from a tray off the Kit-tab header and via the catalog's "Switch
  library…" footer; the tab list re-renders behind the tray, which is how the
  app-wide scope reads. Lists never HIDE by kit availability (#113
  flag-don't-hide, extended 2026-07-25) — grouping mechanics in
  `navigation.md`; unavailable gear reads in notes amber ("needs X", card
  pills) on rows. The **Exercises tab IS the whole catalog** (2026-07-17): an
  exercise is a thing you choose to do, not property — curation is FAVORITES
  (`Exercise.isFavorite`; `inLibrary` frozen). The GEAR facet and
  `GearPickSheet` were RETIRED 2026-07-25 (the search field reaches what
  facets reached; persisted `exerciseCatalog.*` keys died with them);
  curation is the MINE tier and the favorite swipe. Copy says "have"/"in your
  kit", never "own" (that word survives only for data ownership) and never
  "have access to" (retired 2026-07-17; permission-grant copy keeps "access" —
  Apple's word). **One possessive for the active kit: "your kit"**
  (2026-07-20; "My equipment"/"YOUR KIT ✓" retired — `GearFit.mine`'s raw
  value stays internal). **Naming the active kit follows one rule**
  (2026-07-20): a switcher CONTROL (the Kit-tab pill, the catalog "Adding to"
  strip, the routine Kit chip) always shows the raw kit name; PROSE and
  verdicts use `EquipmentLibrary.activeNamePhrase` (name the kit once more
  than one exists, else "your kit"). Opening the catalog to change membership
  is always **"Edit your kit…"**. ⚠️ **A kit NAME in a sentence wears the
  data-tag treatment** (2026-07-28): `KitNamePhrase`/`KitTag` give it
  `CardTagCapsule`'s soft r6 fill so it reads as a name, not an adjective
  missing its noun ("Add barbell to main"). The tag only works with the name
  LAST — SwiftUI can't put a padded rounded tag inside a wrapping `Text` run —
  so anywhere it can't go (mid-sentence prose, a saturated button cap) the
  name takes its noun instead, via `EquipmentLibrary.activeKitPhrase` ("the
  main kit"). The bug is invisible until a SECOND kit exists, since prose says
  "your kit" until then. The user-facing term is "kit", the fourth tab is
  labeled **Kit** (2026-07-20), and **"gear" is retired** from user-facing
  copy — **kit** for the your-set sense, **equipment** for the single-item /
  catalog sense ("Equipment catalog" keeps its name). `EquipmentLibrary` the
  type, `AppTab.equipment`, and the interchange's
  `program/equipment-libraries/` path are frozen internals.
