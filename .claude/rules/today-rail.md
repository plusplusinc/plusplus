---
paths:
  - "PlusPlus/Views/TodayView.swift"
  - "PlusPlus/Views/Components/AnytimeCard.swift"
---

# Today's rail: the band, the entries, the pull

Split out of `navigation.md` on 2026-08-02, at 24,411 of its 24,576-byte
budget. It was never tab-bar or search architecture — it is one surface's
layout, learned build by build — and it loaded on every file under
`PlusPlus/Views/**` to say so. Scoped here, it reaches the two files it
actually governs. ⚠️ The split was RELOCATION, not compression: nothing was
dropped, and nothing here should be compressed to make room. If this file
approaches its own cap, split it again (the pull and the band are separable).

Every ⚠️ is a law learned on device, and the build number names the failing
build. Siblings: `navigation.md` (tab bar, search, scope control, tab-root
chrome, landings), `design-grammar.md` (color/key/tag/motion/copy),
`app-surfaces.md` (what each screen is), `ui-interaction.md` (gesture laws).

## The band, the rail, the landmarks, the pull

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
  ⚠️ **ONE lazy container on this axis, and every rail row is a DIRECT child
  of it** (2026-08-07). A `LazyVStack` nested inside that pinned-header one
  realizes NO children, so Today draws as a viewport of BLANK SPACE — the
  large title, the ++ key and the tab bar all fine, the timeline simply
  absent. Build 163 (#532) nested one to scope the below-anchor `minHeight`
  and shipped that on every install for six days: `ui-test` went red on the
  push and stayed red, but it is not a required check and its tracking issue
  was ALREADY OPEN, so the mechanism that files one said nothing, and the
  four failing assertions carried no message (`todayInventory()` now exists
  for exactly this). Do NOT reintroduce an inner lazy stack to scope a
  frame: a frame that wraps a subrange of these rows has to wrap them
  eagerly, and eager history is the O(sessions) render the bug hunt killed.
  The `minHeight` therefore sits on the WHOLE stack, which #532 was right
  to call imprecise — a tall week ahead eats it and leaves today short of
  the very top on a nearly-empty timeline. That imperfection is the price
  of a surface that renders at all.
  ⚠️ Two more riders, both invisible until they bite. The landing's anchor is
  a zero-LAYOUT overlay held one band-height ABOVE that block's bottom, its
  height DERIVED from `UIFont` (never probed — a state write during layout
  anywhere in the TabView subtree breaks the search-role morph, and Today is
  inside it; `navigation.md`): `scrollTo` ignores pinned headers, so a bottom-seated
  anchor puts today's first row BEHIND the band. And the
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
  belongs to the band (the first law in this file), and a second section
  would take it the moment history came into view.
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
