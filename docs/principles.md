# Principles

What we believe about excellent products, what this product believes in particular, and what
the work of building it aims for. A brief argues from these; a review judges UI against them;
the retro judges the work against its aims. When a proposal and a principle disagree, the
principle wins or gets changed here, on purpose.

## Any excellent product

1. **Solve a real problem for a specific person.** Vague audiences produce vague products.
   Know exactly who is using it, what they are trying to accomplish, and what "done" looks
   like from their chair. Everything else is downstream of this.
2. **Do less, better.** Fewer features executed to a high standard beat many features
   executed adequately. Every addition costs comprehension, maintenance, and the coherence of
   the whole. The hardest and most valuable skill is saying no.
3. **Make the default path obvious.** Users should not have to think about how to do the main
   thing. Progressive disclosure earns its keep here: the surface stays simple, and depth
   appears only when someone reaches for it.
4. **Speed is a feature.** Latency erodes trust and flow in ways users rarely articulate but
   always feel. Fast software feels more capable than it is; slow software feels broken even
   when it works.
5. **Reliability before novelty.** People forgive missing features far more readily than they
   forgive losing work or being surprised by inconsistent behavior. Predictability is the
   foundation of trust.
6. **Design for the whole range of users.** Accessibility, keyboard support, small screens,
   poor connections. Constraints like these tend to sharpen the design for everyone, not just
   the people they are nominally for.
7. **Ship, observe, iterate.** No amount of upfront planning replaces watching real people use
   the thing. Short feedback loops and instrumentation beat clever guesses.
8. **Keep the internals as clean as the surface.** Technical quality and product quality
   converge over time. A codebase that is easy to change lets you respond to what you learn;
   one that is not quietly locks the product into its first draft.
9. **Care about the details nobody asked for.** Error messages, empty states, copy,
   transitions. These are where users decide whether the makers were paying attention, and
   they are usually right.

## This product

1. **Built for the moment of use.** One hand, mid-set, sweaty, no attention to spare. Anything
   on the workout screen is judged in that moment, not at a desk.
2. **Feels simple, is not simple.** The product can be powerful, flexible, and rich, but no
   moment of using it feels overwhelming or complicated. Power arrives through progressive
   disclosure, and by composing small things rather than configuring big ones.
3. **Adding is cheap, removing is not.** A feature, option, or setting exists only once there
   is validated, high-confidence evidence of its value. The default answer is no, and the
   burden of proof is on the addition.
4. **Native bones, own soul.** System navigation and controls wherever the platform already
   does the job well. The brand lives in a few signature moments, such as logging a set and
   resting between sets, not in reinvented standard controls.
5. **The user is in control.** They build and schedule their own workouts. Simplicity never
   comes from withholding control.
6. **Reasonable defaults.** The first workout is minutes away without any setup, and every
   default is something the user can change. A default is a starting point, not a decision made
   for them.
7. **Your data is yours.** Workouts and health data stay on the user's devices and in their own
   iCloud. No account to create, nothing held hostage. The one exception is anonymous usage
   analytics, which the user can turn off.

## What the work aims for

Agents build the product, led by a main session, the lead (`CLAUDE.md`, "Building features"),
for a maintainer who decides what it should be. The work aims for three things:

1. **The right product.** The lead knows what the maintainer means, for the product and its
   users. Where the maintainer isn't clear yet, the lead helps them find out: a question with a
   recommendation, a brief that argues, a thin slice in their hands. It does not guess.
2. **Built right.** What ships holds to the principles above, and the work lands the first time:
   few failed runs, few rounds the lead caused, nothing broken after a merge.
3. **Mostly autonomous.** The maintainer's time goes to product calls and trying builds, not to
   correcting the lead or running tools.

### Who owns what

- **The maintainer owns the product**: its direction and every product decision. What it
  does and for whom, how it looks, reads, and feels, what comes next, and what is left out.
  The lead helps them decide: options with a recommendation, a brief that argues, a build in
  their hands.
- **The lead owns the codebase**, as its architect, and answers for its technical health:
  the architecture and its abstractions, the shape of stored data, tests, tooling, CI,
  dependencies, and when to refactor or pay a debt down. It decides these and acts on them
  without asking, and tells the maintainer in a line what landed, in terms of the product.
- **The line between them.** A technical choice is a product decision when it changes what a
  user sees or can do, changes or risks their data, spends money, or closes off a direction
  the product might take. The lead brings those with a recommendation. Everything else
  technical is the lead's call, and asking the maintainer to make it is a cost to them.

### What the codebase is for

1. **To deliver the product's observable behavior**: the UI, the interactions, the
   performance, what it does, and that it does it every time.
2. **To make the next product change small.** The codebase's value is leverage: how little
   has to change underneath for the product to gain a capability. That comes from the right
   abstractions, small parts that compose, so a new capability is mostly an arrangement of
   what exists.

The second job is the lead's standing work, and it has a measure: the size of the change a
new capability took. A small capability that needed a large change is a finding, for the
retro and for a card.

- **Before a slice, make the change easy.** Ask what shape the code would have for this
  capability to be small, and get it to that shape first, as part of the slice or as a card
  of its own ahead of it. Then make the easy change.
- **Leverage is earned from evidence, never guessed.** An abstraction is drawn from code that
  exists and from what the board says is coming, not from what might be needed
  (`CLAUDE.md`, "Lean"). A second use, or a queued card that will need it, is evidence; a
  hunch is not. A wrong abstraction costs more than a missing one.
- **Say what a product ask costs.** When something the maintainer wants is expensive in the
  code as it stands, the lead says so, with a cheaper shape of the same idea if there is
  one, and what would make it cheap. The decision stays theirs.
- **Health is never traded for a date without saying so.** A shortcut taken to get a build
  into the maintainer's hands is named when it is taken, and paid back before the slice
  merges or carded.

Getting better at them is a loop: notice what trips the work up when it happens (friction, waste,
a missed chance, anything odd), record it (a PR's Friction line, the conversation), review it on
a schedule (the retro, `.claude/skills/retro/SKILL.md`), make the change at the lowest altitude
that can hold the fix, and check that the fix worked.
