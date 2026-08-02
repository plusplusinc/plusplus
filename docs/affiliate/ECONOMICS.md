# The affiliate business — economics and a plan

**Compiled 2026-08-02.** Modelling only. No commitments, no applications made.

---

## The headline

**Affiliate links will not reach $1,000,000/year at any PlusPlus scale that is
realistically in reach — as a link on a detail page.** In that form the model
needs roughly **20 million monthly actives**, which is not a target, it's a
refutation.

The model becomes *arguable* at around **1,000,000 MAU**, and *plausible* at
around **400,000 MAU**, but only if three things are true that are not true of
a normal affiliate integration:

1. The recommendation lands on a **four-figure basket** (a home gym build-out),
   not an $80 kettlebell.
2. Attribution runs on a **discount code**, not a cookie.
3. Commission comes from **direct deals at 8–10%**, not self-serve at 4–5%.

The single most useful thing in this document is the ranking in §4: **the
commission rate — the number everyone shops for first — is the least important
lever in the model.**

---

## 1. The model

Revenue decomposes into five multipliers. Keeping them separate is what makes
the result diagnosable instead of a single guessed number.

```
annual revenue = MAU
               × click rate          (share of actives who tap a product link in a year)
               × win rate            (share of those who buy AND we win last-click attribution)
               × AOV                 (average order value of what they buy)
               × commission rate
```

**Cross-check.** The same result via industry EPC: ecommerce affiliate EPC
averages **$0.65/click**, conversion **1–3%**. Both methods below agree within
~15%, which is the main reason to trust the shape even where the inputs are
guesses.

⚠️ **Every input is an estimate.** Two are sourced (AOV anchors, EPC); three
are judgment. The point of the model is the *sensitivity*, not the point
estimate — see the interactive version for moving them yourself.

---

## 2. Three scenarios

### Scenario B — the detail-screen footer

The safe first placement from PROTOTYPES.md §B.

| Input | Value | Reasoning |
|---|---|---|
| Click rate | 8%/yr | Equipment detail is three taps deep. Most users never open it. |
| Win rate | 4% | High intent, but a 6-week consideration cycle vs. a 21–30 day cookie, minus coupon-extension leakage. |
| AOV | $280 | Blended; skewed small because whatever type you're viewing is what you buy. |
| Commission | 5% | Self-serve blend of Amazon 3% / Rogue 4% / Titan 5% / REP 8%. |

**→ $0.045 per MAU per year.** (EPC cross-check: 0.08 × $0.65 = $0.052. ✓)

**$1M requires 22,000,000 MAU.** At a realistic 100,000 MAU this earns
**$4,500/year.**

### Scenario A — want list + kit builder, executed well

Approach A from PROTOTYPES.md, with codes and direct deals.

| Input | Value | Reasoning |
|---|---|---|
| Click rate | 10%/yr | 25% mark something wanted (one-tap curation on a tab they already use); 40% of those tap through. |
| Win rate | 12% | **A discount code, not a cookie.** Survives the consideration cycle, the review-site detour, and the browser extension. This is the 3x. |
| AOV | $420 | The builder biases toward what opens the most exercises: racks, benches, barbells. |
| Commission | 8% | Negotiated direct. PRx already publishes a path to 12%. |

**→ $0.40 per MAU per year.** Plus the build-out line below.

### The build-out line — where the real money is

Different unit of analysis. Not clicks per user; **basket events**. A
foundational home gym (bench, weights, a machine) averages **$2,837**.

| Input | Base | Optimistic |
|---|---|---|
| Share of MAU doing a build-out in a year | 3% | 5% |
| Share of those PlusPlus wins | 8% | 15% |
| Commission | 8% | 10% |

**Base: $0.545/MAU/yr. Optimistic: $2.13/MAU/yr** (the optimistic case also
lifts the want-list line to $0.50 by carrying the same 10% commission).

**Combined with the want-list line:**

| Case | Per MAU/yr | MAU for $1M |
|---|---|---|
| Scenario B only | $0.045 | 22,000,000 |
| A + builder, base | $0.95 | **1,053,000** |
| A + builder, optimistic | $2.63 | **380,000** |

---

## 3. What that means at scales that actually exist

| MAU | Scenario B | A + builder (base) | A + builder (opt.) |
|---:|---:|---:|---:|
| 1,000 | $45 | $950 | $2,630 |
| 10,000 | $450 | $9,500 | $26,300 |
| 50,000 | $2,250 | $47,500 | $131,600 |
| 100,000 | $4,500 | $95,000 | $263,000 |
| 400,000 | $18,000 | $380,000 | **$1,052,000** |
| 1,000,000 | $45,000 | **$950,000** | $2,632,000 |

**The uncomfortable row is the top one.** For the first year or two after
launch, affiliate revenue will not pay for the time spent building it. Its
value in that window is **learning** (real EPC data, which no blog post will
give you) and **user utility**, not money. Any plan that treats it as near-term
income is wrong.

**The comfortable finding:** maintenance is roughly 16 hours/year of link
upkeep. At the base rate, that cost is covered at about **2,500 MAU**. So the
feature pays for its own upkeep almost immediately — it's the *setup* cost and
the *opportunity* cost that dominate, not the running cost.

---

## 4. Sensitivity — which lever to pull, in order

Every input is a linear multiplier, so what ranks them is **how far each can
realistically move**.

| Lever | Realistic range | Multiplier | Controllable? |
|---|---|---|---|
| **MAU** | 1k → 400k | **400x** | Yes, but it's the whole app's job, not this feature's |
| **AOV** | $280 → $2,837 | **10x** | **Yes — this is what the kit builder is for** |
| **Win rate** | 4% → 12% | **3x** | **Yes — a discount code does this** |
| Click rate | 8% → 25% | 3x | Partly; placement, bounded by taste |
| **Commission rate** | 4% → 10% | **2.5x** | Partly; needs volume first |

**Order of work: AOV, then attribution, then commission.** Chasing the
headline commission percentage — the instinct everyone has, and the thing every
affiliate roundup article ranks by — is chasing the smallest lever in the
model.

Concretely: moving a user from *"here's a barbell"* to *"here are the four
pieces that open 112 exercises, in the order to buy them"* is worth more than
doubling the commission rate. And it is a better product.

---

## 5. The comparison Dave actually needs

The same engineering effort pointed at a subscription (per #94's freemium
recommendation: core tracking free forever, Pro for the convenience layers).

At **$29.99/year**, Apple Small Business Program (15%) → **$25.49 net**.
**$1M = 39,200 subscribers.**

| Free → paid | MAU for $1M |
|---|---|
| 4% | 981,000 |
| 8% | 490,000 |
| 12% | 327,000 |

**Side by side at 100,000 MAU:**

| Line | Annual |
|---|---|
| Affiliate, scenario B | $4,500 |
| Affiliate, A + builder (base) | $95,000 |
| Affiliate, A + builder (optimistic) | $263,000 |
| Subscription at 6% conversion | $153,000 |
| **Subscription + affiliate (base)** | **$248,000** |

Three things fall out of that table:

**They need similar scale.** Affiliate isn't the cheap shortcut to revenue that
it looks like from outside. Both roads run through roughly the same number of
users.

**Subscription is more predictable and less fragile.** No third party can halve
it overnight — and Amazon did exactly that to affiliate rates across categories
in April 2020, with no notice.

**They don't compete for the same user, which is the actual argument for doing
both.** Affiliate monetizes the free user who will never subscribe. And the kit
builder can be a **Pro feature that also carries affiliate links** — one piece
of work on both revenue lines.

**$1M/year is realistically ~400,000 MAU with both lines running.** That is the
honest answer to the question as asked.

---

## 6. Costs and risks

**Setup:** ~40 hours — plusplus.fit gear pages, four program applications, the
product link table, the app surface. **Maintenance:** ~4 hours/quarter, growing
with catalog coverage; links rot as products are discontinued.
**Marginal cost per transaction: zero.** **Tax:** 1099-MISC, self-employment
income; not a structuring question until it's material.

**Opportunity cost is the real number.** Those same 40 hours on StoreKit 2 and
a paywall open a line worth 10–30x more at the same scale.

| Risk | Mitigation |
|---|---|
| Unilateral rate cuts | Never let one program exceed 40% of revenue. |
| Program termination | Same. Four programs, not one. |
| Coupon-extension leakage (20–30%) | Codes, not cookies. |
| Cookie window < consideration cycle | Weight Rogue's indefinite window over REP's higher rate. |
| **Brand damage** | **Structural, not monitored:** rank by unlock count only, and say so in the disclosure where users can hold the app to it. |

The last one has no financial mitigation. *A hackable workout tracker for
incrementing yourself* is one bad placement from reading as a storefront, and
that is not a reputation you get back. Every number above is worth less than
that sentence.

---

## 7. Phased plan, with gates and a kill criterion

**Phase 0 — off-app (now, ~1 weekend).** Gear guide pages on plusplus.fit.
Apply to Rogue, REP, Titan. This is a **prerequisite**: most programs require a
live site with traffic, and a TestFlight build has no public URL to put on the
form.
→ *Gate:* 2+ approvals, and ≥$100 earned from the site in 3 months.

**Phase 1 — the footer (post App Store launch).** `EquipmentDetailScreen` gets
WHERE TO GET ONE. No prices, no tracking, system browser. Per #94, nothing
ships before launch.
→ *Gate:* click rate ≥5% of MAU/yr **and** EPC ≥$0.50.

**Phase 2 — the want flag + codes.** `Equipment.isWanted`, the wanted section,
and a direct conversation with two brands about a PlusPlus code.
→ *Gate:* ≥15% of MAU mark something wanted.

**Phase 3 — the kit builder.** "Four pieces open 112 exercises, cheapest unlock
first." The only phase that changes the revenue picture — and the only one
worth building as a Pro feature independent of whether it ever carries a link.

**Kill criterion, agreed in advance:** if six months of Phase 1 shows EPC under
$0.25, **remove the surface**. A dead commerce section earning nothing while
carrying the brand risk is the worst of both outcomes, and the instinct will be
to leave it there and hope.

---

## 8. Recommendation

**Do it — as a margin business, third in line.**

1. **Phase 0 this month.** It's a weekend, it's off-app, it carries no risk,
   and it's the only way to get real EPC data instead of blog-post averages.
2. **Subscription is the primary line.** #94 already concluded this and the
   numbers here support it. Affiliate should not delay StoreKit work by a day.
3. **Build the kit builder for its own sake.** *"These four pieces open 112
   exercises"* is a genuinely novel feature that no competitor has, because no
   competitor models equipment as a first-class thing with reach math over it.
   It is a good Pro feature whether or not a single link is ever attached — and
   attaching links to it later is the only version of this business that
   reaches seven figures.

The order matters: build the feature because it's good, then monetize it.
Doing it the other way around produces a worse feature and, on these numbers,
not much more money.
