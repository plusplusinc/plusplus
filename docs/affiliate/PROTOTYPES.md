# Weaving product links into the app — five approaches

**Compiled 2026-08-02.** Design exploration. **No app code has been changed.**

Five shapes, ranked worst-to-best fit, then the three decisions that apply to
whichever one gets built. Each is described against the surfaces that already
exist — this app has an unusually good substrate for this, and most of the work
is choosing which existing thing to hang one section off.

---

## What the app already has

Worth stating plainly, because it decides everything below:

- **`Equipment` is a first-class model**, with a built-in catalog of ~100
  generic types (`EquipmentCatalog.swift`) and a deliberate **no-brand-names
  rule** (#222). Product recommendation is the first feature that ever wants to
  cross that line.
- **`EquipmentDetailScreen`** already exists as a real destination in the
  cross-reference graph (exercise → equipment → routine).
- **`CatalogReach`** already computes, per kit, how much of the catalog is
  doable — split by muscle group and movement pattern. Its own doc comment says
  the frame is *"what this opens"*, never *"what you lack"*.
- **`MissingEquipmentHeaderRow`** already groups what your kit can't do, under
  the flag-don't-hide law (#113).
- **`EquipmentResolveSheet`** already models a missing piece as a **routed
  decision**: switch kits, add to kit, or swap the exercise. It has a slot
  shaped exactly like a fourth route.
- **`SafariView`** (SFSafariViewController) already exists.
- **`EquipmentLibrary.switchingBlurb`** already says *"add to your kit to
  unlock more exercises."* The app has been making the argument for buying
  equipment since July. It just doesn't finish the sentence.

---

## E. Off-app: gear guides on plusplus.fit

**No app change at all.** Equipment guide pages on the existing site, one per
major type, each with real editorial content and affiliate links. The app's
`EquipmentDetailScreen` gets at most one plain outbound link.

**For:** zero App Store risk. Zero privacy compromise. Full FTC control in a
medium built for it. **It is the only approach that works before the app has
users** — and it solves the application gate from PROGRAMS.md §5, since most
programs require a live site with traffic before they'll approve you. SEO
revenue is independent of installs.

**Against:** doesn't use the app's unique asset. Anyone can write gear guides,
and Garage Gym Reviews already does it better with a decade of head start.

**Verdict: build this first regardless of which in-app approach wins.** It is a
prerequisite, not an alternative. It also produces the only honest EPC data
Dave will have before committing app surface to this.

---

## D. A fourth route in the resolve sheet

`EquipmentResolveSheet` opens from the amber "needs X" chip in the routine
header and offers: switch to a kit that covers this · add it to your kit ·
swap the moves. Add **"Get one"** as a fourth route.

**For:** structurally free — the sheet is already a route list with a
lead-with-the-best-fix ordering.

**Against, and it is disqualifying:** this is the single highest-pressure
moment in the app. The user is mid-plan and blocked. A purchase route there is
the app monetizing an obstacle it created by filtering the catalog. That is
the exact shape of a dark pattern, and it would read as one whether or not it
was meant as one.

**Verdict: no.** Keep the resolve sheet clean. The one thing it must never do
is make being blocked profitable.

---

## C. A section on the missing-equipment disclosure

The disclosure header says *"34 exercises require more equipment."* Expand it
to name the single piece that opens the most, with a product beneath.

**For:** the unlock math (`CatalogReach`) is genuinely the most useful thing
the app knows, and *"a squat rack opens 34 more exercises"* is a fact worth
stating **whether or not anything is sold**.

**Against:** the disclosure is deliberately **neutral ink, never amber** —
its doc comment says an amber header "would read as an alarm over a whole
group." Putting commerce in a component built to be quiet inverts its purpose.
And it appears on every catalog list, so the link is everywhere.

**Verdict: take the unlock math, leave the commerce.** Ship "one piece opens
the most" as a free feature on its own merits. If it proves people tap it, the
product link can come later, on the detail screen it pushes to.

---

## B. A footer on `EquipmentDetailScreen`

One section at the bottom of equipment detail: **WHERE TO GET ONE**, one to
three products, a disclosure line, nothing else.

**For:** the user navigated here on purpose. Intent is already established and
nothing was manufactured to create it. It is one screen, easy to build, easy to
remove, easy to A/B by simply not shipping it. It respects the existing
detail-screen grammar (a pushed detail screen with a dynamic name, per
design-grammar).

**Against:** low traffic. Equipment detail is three taps deep and most people
will never open it. Expect this to earn very little.

**Verdict: this is the right first in-app placement** precisely *because* it
earns little. It measures the click rate at near-zero brand risk.

---

## A. The want flag — recommended

**A curation flag on `Equipment`, not a kit.**

```swift
// PlusPlus/Models/Equipment.swift — sketch, not implemented
/// Marked as wanted: gear the user has said they'd like, which is NOT
/// availability. Deliberately NOT a kit — a kit answers "what can I do
/// here", and folding wanted gear into one would make CatalogReach
/// promise exercises the user cannot actually do.
var isWanted: Bool = false
```

This works because of three things already true in the codebase:

1. **The curation precedent exists.** `Exercise.isFavorite` is exactly this
   shape, and the swipe law is already **LEADING is curation, TRAILING is
   destructive**. On the Kit tab, leading currently carries ADD/REMOVE
   membership; a WANT action joins it on the same edge, in `Theme.swipeNeutral`
   (the same neutral UNFAV and REMOVE take — it is reversible, so it isn't
   destructive red).
2. **It cannot corrupt the reach math.** `CatalogReachCalculator.canDo` tests
   membership in the active kit. A separate flag never enters that set, so
   "doable" stays honest. Folding wanted gear into a kit would break this, which
   is why it must not be a kit.
3. **It inverts who starts the conversation.** The user says "I want a squat
   rack." The app answers. Every other approach has the app raising the subject.

**The surface** is a *wanted* section on the Kit tab — under MINE, above
CATALOG — with the unlock math attached: *"A squat rack opens 34 more
exercises."* That list, and only that list, carries products.

**And the second-order feature is where this gets interesting.** Once several
pieces are marked, the app can answer a question nothing else on the market
can: *"here is the order to buy these in, cheapest unlock first."* `CatalogReach`
already has every input. That is the **kit builder**, and ECONOMICS.md §5 argues
it is the only version of this business that reaches meaningful revenue.

**Against:** the most code. New model field (optional additive property →
lightweight migration, per the swiftdata rules), new section, new interchange
consideration (does a want list export? Probably yes — it's the user's data).

**Verdict: recommended as the destination.** B is the way to get there safely.

---

## The three decisions that apply to all of them

### 1. No prices. No product feed. No images. Ever.

The app shows a **product name and a link**. Nothing else.

This one decision removes almost every hard problem:

- **No staleness.** Prices in a shipped binary are wrong within a week and
  wrong-price-in-app is a trust injury out of proportion to the feature.
- **No Amazon API compliance.** Amazon's price-refresh-within-24-hours rule
  cannot be violated by an app that never displays a price.
- **No fetch.** No manifest download, no CDN, no "phones home" argument to
  have. Nothing about this feature makes a network request until the user taps.
- **No infrastructure.** A static Swift table, updated when the app updates.

The link goes to the product page. The seller's site is the authority on price
and stock, which is also true and worth saying in the disclosure.

### 2. Rank by unlock count, never by commission — and say so

The ordering rule is a **product commitment**, and it belongs in the disclosure
copy where users can hold the app to it:

> Buying through these pays PlusPlus a commission. Nothing here is ranked by
> what it pays.

That clears the FTC bar (clear, conspicuous, adjacent, visual, plain) and the
voice bar (no "we"/"I"; the sanctioned `PlusPlus` self-reference; consequence
first; two short sentences; no em dash). The second sentence is mechanism, which
the voice principles permit exactly where mechanism buys trust.

If the ranking ever becomes commission-influenced, that line has to come out —
which is the point of putting it there.

### 3. Open the **system browser**, not `SafariView`

Non-obvious and load-bearing for revenue: **`SFSafariViewController` uses a
data store isolated from Safari.** A user who taps a link, browses, closes the
sheet, and completes the purchase in Safari a week later has left the affiliate
cookie behind in a container that no longer exists. Use `openURL`.

REP's IP-based fallback (cookies **and IPs** stored 21 days) partly rescues the
in-app case, and Rogue's indefinite window helps, but neither is a reason to
choose the worse mechanism. `SafariView` stays what it is today: the GitHub
tray's in-app flow.

**Corollary: the app records nothing.** No click counts, no analytics, no
identifiers. Attribution rides the affiliate network's own subid in the URL,
which is enough for reporting and requires zero collection on the app's side.
That keeps App Store guideline 5.1.1(ii) out of scope and leaves *PlusPlus
never phones home* literally and defensibly true.

---

## Copy candidates

Drafted against `.claude/skills/voice/SKILL.md`. **Run `copy-reviewer` on any
of these before they ship** — this is a first pass, not cleared copy.

| Surface | Candidate | Check |
|---|---|---|
| Section label | `WHERE TO GET ONE` | All-caps mono is section-labels-only ✓ |
| Disclosure | "Buying through these pays PlusPlus a commission. Nothing here is ranked by what it pays." | No we/I ✓ · sanctioned self-reference ✓ · two sentences ✓ · no em dash ✓ |
| Unlock fact | "A squat rack opens 34 more exercises." | Consequence first ✓ · "opens" not "you lack" ✓ · no obligation ✓ |
| Want swipe | `WANT` | Leading edge = curation ✓ · `swipeNeutral` ✓ |
| Wanted section | `WANTED` | — |
| Empty wanted list | "Nothing marked yet. Swipe any equipment to mark it." | Fragment house style ✓ · states the gesture ✓ |
| Builder result | "Three pieces open 112 more exercises." | Fact, no price, no urgency ✓ |

**Deliberately avoided:** "Buy now", "Shop", "Deals", "Recommended for you",
anything with a price, anything with urgency, anything with a badge. Also
avoided: **"unlock" as a verb in new copy** — `switchingBlurb` has it and that
line is canonical, but repeating it around commerce turns a training word into
a game-monetization word.

---

## What would have to be true to ship any of this

- The App Store launch has happened (per #94: "Nothing ships before the App
  Store launch").
- plusplus.fit gear pages exist and at least one program has approved the
  application.
- The no-brand-names rule (#222) has an explicit, dated exception in
  docs/DECISIONS.md. It currently governs the **catalog**; products are a
  different layer, and the distinction should be written down before it is
  relied on rather than after.
- `copy-reviewer` has passed every string.
- The FTC disclosure appears **on every surface carrying a link**, not
  centralized.
