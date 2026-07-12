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
  one VIVID blue on screen outside a live ring gesture. `Theme.selected` is
  retired as a text/link color; escape hatches are quiet keys. Exception
  (2026-07-12, #superset-feedback): the settled superset return-loop draws in
  `Theme.supersetLoop` (the selection hue at ~50%, a deliberately quieter
  tone) so a grouped block reads as a bound unit; the full-chroma selection
  blue still means "live". On a ring-drag landing the loop blooms up to full
  `selected` for ~0.4 s (the departed selection field collapsing onto it),
  then settles back.
- **Purple is done** (GitHub-merged mapping): committed rail rings, session
  pips, the finish checkmark, widget streak squares.
- **RaisedKey press grammar**: every committing/navigating button is an opaque
  cap depressing onto a fixed base plate (4 pt standard / 3 pt quiet, 0.06 s
  ease-out); flat controls (chips, toggles, segments, rows) stay flat.
  Custom key chrome everywhere — `pushedScreenChrome(...)` replaces system
  toolbars on pushed screens.
- **Motion carries meaning, one mechanism each**: selection slides, data
  rolls, completion thuds (impact per set, `.success` only at the purple
  finish), navigation zooms. ~0.15 s ease-out; the app always feels fast.
- **No obligation vocabulary** ("due" is banned) and **anti-shame**:
  regressions render neutral, diffs sum positive movement only, no
  out-of-band warnings.
- **No em dashes in user-facing copy** (Dave, 2026-07-10): rewrite the
  sentence (split it, or use "·" separators) instead. A bare "—" standing
  in for a missing value is a placeholder glyph, not prose, and stays.
- Warm charcoal dark (`#201F1D` family); the watch keeps system black.
- Draw every color from `Theme` — never ad-hoc literals.
- **Equipment is availability, not ownership** (2026-07-11): what gear you
  "have" is membership in the ACTIVE `EquipmentLibrary` (Home, Hotel…),
  switched from a tray off the Equipment-tab header (left of the +) and via
  the catalog GEAR facet's "Switch library…" footer; the tab list re-renders
  behind the tray, which is how the app-wide scope reads. Curated lists
  flag-don't-hide (#113): the Routines/Exercises tabs list everything but
  render unavailable gear in notes amber ("needs X", card pills); only the
  CATALOGS filter by the active library. Copy says "have"/"in library", never
  "own" (that word survives only for data ownership and "My equipment"/"YOUR
  GEAR ✓" selection possessives). The GEAR facet + template verdict name the
  active library once more than one exists (a lit HOME/HOTEL chip, "HOME ✓").

## What the app is, surface by surface

**What works (as of 2026-07-07 late-night, design-v3 end to end):** the Claude Design v3 handoff shipped in one overnight arc — #114 palette, #115 nav, #124 Today+diffs, #125 schedule+onboarding, #126 watch v1, plus the #107 scroll root-cause fix and #127 gesture hardening. The app is four bottom tabs on the native iOS 26 Liquid Glass TabView (#130): Today · Routines · Exercises · Equipment. **Today** — the unified timeline: pending (due) workouts as dashed cards with per-exercise diff summaries (`+5 lb · +2 reps · 1 new · 2 =`), expandable rows, due captions ("due today" / "due since thu"), full-width Start; committed sessions below with net chips (green, up-only); rest-day/first-run timeline items and a swap-in sheet for off-schedule sessions; settings opens here. **Routines** — cards with schedule + equipment pills, header + creates; detail keeps the v2 rail (+ a share button, #145) (drag/ring gestures now on a UIKit recognizer so the list actually scrolls) with schedule/rest chips under the title. **Exercises / Equipment** — pushed detail screens forming a navigable graph (#137: equipment ⇢ exercises ⇢ routines, create-at-every-dead-end); the header + pushes CatalogBrowseScreen (#139: whole catalog listed, membership toggles, All/In-library/Not filters); built-ins editable except name, with revert-to-default (#136). **Sharing** — routine detail → `plusplus.fit/r#…` link (payload in the fragment, never on a server); `plusplus://` links open an import preview (#145). **Onboarding** — setup-as-timeline (#132): no cover screen; a fresh install's Today shows three setup steps as gated timeline entries (equipment → first workout → schedule, bottom-up like commits) that become committed-style cards when done and yield to real history at the first logged session; equipment access re-runnable from Settings → EQUIPMENT ACCESS. **Watch** — WatchConnectivity companion: plan pushed on launch/backgrounding, wrist execution (frozen step list, log/rest/haptics, watch-local rest-over notification, early exit), finished sessions sync back as append-only history with a synchronous acked import. Session records show block-level Δ vs the previous same-workout session. **Platform surfaces (#147, build 17; whole-session in #322)** — a Live Activity spanning the workout (Dynamic Island + Lock Screen): `.working` (exercise · set N/M · count-up elapsed) swapping to `.resting` (countdown + +30s/Skip), driven from ActiveSessionView's lifecycle via `WorkoutActivityController`. #322 also REMOVED the phone rest/timer local notifications (and their permission prompt) — the rest-over cue is watch haptics + the island countdown, not a phone banner; *Due today* and *Streak* widgets (12-week mini contribution row) reading a `WidgetSnapshot` written to the App Group (`group.com.davidcole.plusplus`) on launch/backgrounding; App Intents (StartRoutineIntent / DueTodayIntent / OpenTodayIntent + shortcut phrases — intents read the snapshot, StartRoutine posts `.plusplusStartRoutine` and RootTabView/TodayView react). **Design v4 (2026-07-08, overnight)** — blue selection grammar everywhere (`selected`/`selectedTint`/`selectedRing`; segmented tabs lost their ink fill; one motion rule: 0.15 s ease-out + selection haptics); routine settings and app settings are pushed pages (routine settings = NAME/rename tray/SCHEDULE/rest/notes tray/Delete-with-confirmation; detail header shows plain facts); the Today pending card is name+estimate / Configure capsule / muscles+gear rows / promoted diff; the superset rail redrawn (solid spine, border-colored return loop with chevrons at rest, selection-blue highlight + SUPERSET legend only while the ring gesture is live; SUPER swipe died); onboarding equipment rides the real catalog in setupMode (pinned Done bar; the preset strip died as destructive, #203); TipKit replaced the ambient captions; fresh installs seed the catalog with an EMPTY library (#185). **Build-27 feedback round (2026-07-08 morning)** — completion is PURPLE (#201: `Theme.done`, GitHub's merged pair — committed rail nodes, session pips, the finished checkmark, widget streak squares; green stays data-in-motion, blue stays selection); creation affordances are GREEN everywhere (#202); the populate offer asks from a centered alert on Today with an ask-time count (#204 — the catalog popover floated anchored to nothing); the catalog is EXTENSIVE (#95 content: 157 exercises / 40 equipment, and `loadIfNeeded` is a name-matched top-up so growth reaches existing stores — newcomers arrive catalog-only and un-owned, curation untouched). **Build-28/29 feedback round (2026-07-08 afternoon)** — routine settings: no Save at all (#219 killed it hours after #207 added one — every field commits live, the name on any exit, so the page is simply always saved), Delete nests in an upper-right `…` menu, name/notes edit INLINE (trays deleted; commits also fire in `onDisappear` because swipe-back bypasses `onBack`); the swap-in sheet only opens when a startable routine exists and both empty paths offer creation (which pushes straight into the new routine); tabs are capitalized; selected states are SOLID blue everywhere; **library search is a floating Liquid Glass dock** at the bottom of both catalog tabs (Messages pattern: glass capsule + green + circle that morphs to ✕ while focused — the missing keyboard escape, #213), with scroll-to-dismiss on every list under a search field; **the polish batch** (#216): the segmented-tab pill SLIDES between segments, digits ROLL on step (directional on the set screen), set-logging is an impact thud with `.success` reserved for the purple finish, and cards ZOOM into their screens (routine card → detail, pending card → live workout, committed card → record; off-card starts fall back to the standard transition); **the Today rail speaks the grammar**: green ring = ready to do, grey ring = rest day, fainter ring = gated setup step, purple dot = done; and any session that misses Finish/Discard (crash, or a dismissal path the exit dialog never saw) is salvaged on Today's next appearance instead of becoming an invisible orphan.
