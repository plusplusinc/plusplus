# Equipment affiliate programs — landscape report

**Compiled 2026-08-02.** Research only. Nothing in this document has been
applied to the app, and no program has been applied to.

⚠️ **Confidence note, read this first.** Every brand's own affiliate page
(`repfitness.com/pages/affiliate-program-rep-fitness`,
`support.roguefitness.com`, and both Post Affiliate Pro portals) returns
**HTTP 403 to automated fetches**. The rates below therefore come from search
snippets and affiliate-directory aggregators, not from the merchants'
own pages read end to end. Rates marked ⚠️ conflict across sources.
**Treat every number here as a lead to confirm at application time, not as a
term sheet.** The structural findings (how attribution works, which network
each brand sits on, what the App Store and the FTC require) are the durable
part; the percentages will drift.

---

## 1. The programs

### Tier 1 — brands whose catalog matches PlusPlus's equipment types

| Brand | Commission | Cookie | Platform | Notes |
|---|---|---|---|---|
| **REP Fitness** | up to 8% | 21 days (cookie + IP) | Post Affiliate Pro (self-hosted) | The best headline rate among the serious home-gym brands. Dave named this one; it holds up. |
| **Rogue Fitness** | 4% | **indefinite** | Post Affiliate Pro (self-hosted) | Half REP's rate, but the cookie never expires. For a purchase with a 6-week consideration cycle that is worth more than the extra 4 points. $100 payout minimum, PayPal USD only. No commission on tax, shipping, or returns. |
| **Titan Fitness** | 5% | 30 days | AvantLink + CJ | On real networks, so a **product feed and API exist**. Budget end of the market — lower AOV, higher conversion. |
| **PRx Performance** | 5% → 12% tiered | not published | UpPromote | Rate scales with volume. The only program found with a published path above 10%. Wall-mounted racks — high AOV, and a natural fit for "I have a garage, not a gym". |
| **Synergee** | 10% | not published | own program | Monthly PayPal. Accessories and mid-range gear. |
| **Fringe Sport** | not published | not published | AvantLink | 2–3 business day approval. |
| **Bells of Steel** | **not disclosed publicly** | — | own program | Program exists; terms only by request (`affiliates@bellsofsteel.com`). |
| **Concept2** | not published | — | — | Program exists. Matters because *Rowing Machine*, *Ski Erg*, and *Air Bike* are all in the built-in catalog and Concept2 is the default answer for two of them. |

### Tier 2 — coverage and long tail

| Source | Commission | Cookie | Why it's here |
|---|---|---|---|
| **Amazon Associates** | **3%** (Sports & Outdoors) | 24 hours | Terrible rate, total coverage. The only realistic answer for kettlebells, bands, plyo boxes, jump ropes, sandbags — the ~60% of the catalog no specialist brand will pay for. ⚠️ See the Amazon-specific risks in §5. |
| **Bowflex** | ⚠️ 3% or 10% depending on source | 30 days | Sources disagree badly. Cardio and adjustable dumbbells. |
| **NordicTrack / iFIT** | not published | — | Treadmills, ellipticals, stair climbers. |
| **Onnit** | 15%, 45-day cookie | 45 days | Highest rate found, but it is a **supplements** business with a kettlebell line attached. Recommending supplements is a different product and a different brand risk. Listed for completeness; **not recommended**. |

### Aggregators — one integration, thousands of merchants

| Platform | Reach | Their cut |
|---|---|---|
| **Skimlinks** | 48,500 merchants across 50+ networks | ~25% of commission earned |
| **Sovrn Commerce** (ex-VigLink) | 30,000+ brands | comparable |

Skimlinks claims it negotiates rates "generally double" direct rates, with 55%
of publisher revenue coming from those premium deals — which, if true, more
than covers the 25% haircut. **Worth a real evaluation**, because the
alternative is applying to eight programs individually and maintaining eight
sets of links by hand.

### The networks themselves

- **AvantLink** — the specialist for outdoor/fitness. Carries Titan and Fringe
  Sport. Real product-feed API. Pays the 23rd monthly via Tipalti.
- **ShareASale / Awin** — $50 minimum, paid the 20th monthly.
- **Impact, CJ** — the enterprise networks; CJ carries Titan.
- **Post Affiliate Pro** — *not a network*. It is self-hosted software each
  brand runs its own instance of. **Rogue and REP, the two most important
  brands, both use it.** Consequence: separate application, separate login,
  separate payout, **no product feed, no API, manual link generation.** This is
  the single biggest operational cost in the whole plan and it is easy to miss.

---

## 2. The structural finding that matters more than any rate

**Commission rates in this category are low (3–8%) precisely because order
values are high.** That is not a problem to negotiate around; it is the shape
of the category. The real economics are decided by three things that have
nothing to do with the headline percentage:

**Attribution is last-click, and PlusPlus will almost never be the last
click.** A person buying an $1,100 rack watches YouTube reviews, reads Garage
Gym Reviews, asks Reddit, visits the brand site five times, and waits for a
sale. PlusPlus's honest position in that journey is *first* click — the moment
of realizing a rack is the thing standing between them and 34 exercises. The
commission goes to whoever was last. This is the central economic problem and
§3 of ECONOMICS.md is mostly about it.

**Cookie windows are shorter than the consideration cycle.** REP's 21 days and
Titan's 30 are shorter than the average deliberation on a four-figure purchase.
Amazon's 24 hours is essentially "buy it right now or nothing." **Rogue's
indefinite window is a genuine structural advantage** and should weigh more in
brand selection than its 4% rate.

**Coupon extensions steal the last click at checkout.** Honey and its
descendants overwrite the affiliate cookie on the payment page. Industry
estimates put the leakage at 20–30%.

**The fix for all three is a discount code, not a link.** A PlusPlus-specific
code survives the six-week cycle, survives the Garage Gym Reviews detour,
survives the browser extension, and gives the user an actual discount. It
converts the business from *win the last click* to *own the code*. Getting one
requires a direct conversation with a brand rather than a self-serve signup,
which means it is a phase-2 move, not a day-one one. It is the highest-leverage
item in this entire report.

---

## 3. App Store position: clear, and better than expected

Guideline **3.1.3(e) Goods and Services Outside of the App**:

> If your app enables people to purchase physical goods or services that will
> be consumed outside of the app, you must use purchase methods other than
> in-app purchase to collect those payments.

Physical equipment is not merely *allowed* to link out — linking out is
**required**. Apple takes no cut. This is categorically different from the
digital-content link-out rules (3.1.1(a)), which need StoreKit External
Purchase Link Entitlements outside the US storefront. None of that applies
here.

One guideline does bind, **5.1.1(ii)**: apps collecting user or usage data must
secure consent. It binds only if PlusPlus adds its own click tracking. The
design in PROTOTYPES.md deliberately doesn't, which keeps this clause out of
scope entirely.

Residual risk is low but non-zero: a shopping surface heavy enough to look like
the app's purpose could draw 4.2 minimum-functionality scrutiny. A footer
section on a detail screen will not.

---

## 4. FTC disclosure: the part with actual teeth

16 CFR Part 255, materially tightened June 2023.

- Disclosure must be **clear and conspicuous**, **in or before** the content
  containing the link, **every time**.
- It must be in the **same medium** as the claim — a visual recommendation
  needs a visual disclosure.
- **Not** in a footer, **not** in a bio, **not** on a Settings > About screen,
  **not** vague.
- There is **no small-publisher exemption**.

Practically: a disclosure line sits **in the section**, adjacent to the links,
on every surface that carries one. It cannot be centralized into one legal
screen, which is exactly what an app would naturally want to do. Design for it
up front — see PROTOTYPES.md §6 for candidate wording that clears both the FTC
bar and the voice laws.

---

## 5. Risk register

| Risk | Severity | Notes |
|---|---|---|
| **Unilateral rate cuts** | high | Amazon halved several category rates overnight in April 2020 with no notice. Any plan that depends on today's percentage is fragile. |
| **Amazon mobile-app policy** | **needs verification before any Amazon work** | The Associates Operating Agreement has historically restricted use in mobile apps and required apps to be explicitly declared. Separately, prices pulled via the Product Advertising API must be refreshed within 24 hours — which the "no prices in the app" design in PROTOTYPES.md sidesteps entirely. **Confirm current terms directly before building anything Amazon-shaped.** |
| **Program termination** | medium | Affiliates get dropped in bulk, without cause, with little notice. Never let one program be more than ~40% of revenue. |
| **Coupon-extension leakage** | medium | 20–30%. Codes fix it; links don't. |
| **Application gate** | **immediate blocker** | Most programs require a live site with demonstrable traffic. A TestFlight build has no public URL to put on the form. **plusplus.fit is the asset that unblocks this** and it already exists. |
| **Brand damage** | **highest** | "A hackable workout tracker for incrementing yourself" is one bad placement away from reading as a storefront. This is the risk that can't be recovered from, and it's the one the design has to be built against rather than monitored for. |
| **Privacy promise** | high | The app says *PlusPlus never phones home*. An affiliate link hands the user to a third-party tracker. Literally the promise still holds — there is no PlusPlus server — but the spirit is what people will judge. See PROTOTYPES.md §5, which resolves this. |

---

## 6. Recommended shortlist

Applying to everything is the wrong move: eight programs is eight logins, eight
payout thresholds, and a link table that rots. **Start with four.**

1. **Rogue** — the indefinite cookie is worth more than any rate on this page.
2. **REP** — best rate among serious brands, and the one Dave already flagged.
3. **Titan** — via AvantLink, which brings a product feed and covers the budget
   end where conversion is highest.
4. **Amazon Associates** — coverage for the long tail only, at a bad rate,
   pending the §5 verification.

Evaluate **Skimlinks** in parallel as a possible replacement for the whole
list. If its negotiated rates are real, one integration beats four.

Defer **Concept2** and **PRx** to a second wave — both are strong fits (cardio
and wall-racks respectively), but four programs is the most one person should
maintain while learning whether any of this converts at all.

---

## Sources

- [REP Fitness Affiliate Program](https://repfitness.com/pages/affiliate-program-rep-fitness) · [directory listing](https://www.postaffiliatepro.com/affiliate-program-directory/rep-fitness-affiliate-program/)
- [Rogue Fitness Affiliate Program](https://www.roguefitness.com/rogue-affiliate-program) · [support article](https://support.roguefitness.com/hc/en-us/articles/48180736139796-Rogue-Fitness-Affiliate-Program)
- [Titan Fitness Affiliate Program](https://titan.fitness/pages/affiliate-program)
- [PRx Performance Affiliates](https://prxperformance.com/pages/affiliate-page) · [UpPromote case study](https://uppromote.com/case-study/prx-performance/)
- [Synergee Affiliate Program](https://synergeefitness.com/pages/affiliate-program)
- [Bells of Steel Affiliate Program](https://bellsofsteel.com/pages/affiliate-program)
- [Skimlinks — Merchants](https://www.skimlinks.com/merchants/) · [Sovrn Commerce](https://www.sovrn.com/commerce/)
- [Amazon affiliate commission rates by category](https://getlasso.co/amazon-affiliate-commission-rate/)
- [Fitness affiliate program roundups](https://backlinko.com/fitness-affiliate-programs) · [Commission Academy](https://commission.academy/blog/best-fitness-equipment-affiliate-programs/) · [WodGuru](https://wod.guru/blog/fitness-affiliate-programs/)
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) — 3.1.1, 3.1.3(e), 5.1.1(ii)
- [16 CFR Part 255](https://www.ecfr.gov/current/title-16/chapter-I/subchapter-B/part-255) · [FTC Endorsement Guides PDF](https://www.ftc.gov/system/files/ftc_gov/pdf/P204500%20Guides%20Concerning%20Endors%20and%20Testimonials.pdf)
- [Affiliate marketing benchmarks 2026 — CVR, EPC](https://www.dollarpocket.com/affiliate-marketing-benchmarks-2026)
- [Home gym equipment statistics](https://chestpressmachine.com/home-gym-equipment-statistics/) · [US home fitness equipment market](https://www.fortunebusinessinsights.com/u-s-home-fitness-equipment-market-106595)
