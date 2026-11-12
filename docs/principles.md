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

The codebase is the product's accumulated understanding in a form that runs: its code, its
structure and patterns, its tests, and the tooling around it. Its worth is how quickly and
safely it turns product intent into excellent behavior, now and for every change after. It
does five things:

1. **It is the product.** What people see and feel (the UI, the interactions, correctness,
   speed, reliability) exists only as this code.
2. **It models the product's ideas.** Its types, names, and boundaries are a theory of what
   the product is: a routine, a workout, a set, a rest. When the model matches how the
   maintainer thinks about the product, a product idea maps straight onto a change, and
   capabilities compose. When it doesn't, every idea is translated first and comes out slow
   and bent. The right abstraction is one of the product's real concepts, found and named.
3. **It remembers.** Every decision, edge case, and fixed bug is recorded in it, and a test
   holds each in place. The agents who build it start every session knowing nothing, so its
   structure and names are how the next builder comes to understand the product.
4. **It makes change safe and feedback fast.** Tests, CI, and tooling let it be changed
   boldly, with an answer in minutes on whether it still does all it did. The loop from an
   idea to a build in the maintainer's hand to a verified merge is part of its worth.
5. **It makes quality the default.** Shared parts and patterns (the design system, the
   motion's timings, how a view is hidden from VoiceOver) make the easy way to build
   something the right way, so excellence does not rest on someone remembering.

**The measure is proportion.** The cost of a change is in proportion to the idea, and its
result is predictable. A simple idea is simple to build; an idea that is hard for the product
may fairly be hard in the code. A simple idea that was hard to build means the model is wrong
somewhere, and finding and fixing that is the lead's job. The size of a diff is not the
measure: the right change is sometimes a large reshaping.

How the lead holds the code to this:

- **Leverage is earned from evidence, never guessed.** An abstraction is drawn from code that
  exists and from what the board says is coming (`CLAUDE.md`, "Lean"). A second use, or a
  queued card that will need it, is evidence; a hunch is not. A wrong abstraction costs more
  than a missing one.
- **Say what a product ask costs.** When something the maintainer wants is expensive in the
  code as it stands, the lead says so, with a cheaper shape of the same idea if there is one,
  and what would make it cheap. The decision stays theirs.
- **Health is never traded for a date without saying so.** A shortcut taken to get a build
  into the maintainer's hands is named when it is taken, and paid back before the slice
  merges or put on a card.

The code is refined toward this continually, at four points, each one a place the work
already passes through:

1. **Before a slice, the planner reads the model.** It says what the capability is in the
   product's terms and whether the code has that concept. Where a simple capability needs a
   plan that isn't simple, the plan names what in the model makes it hard and reshapes that
   first, or the lead makes it a card ahead of the slice. Make the change easy, then make the
   easy change.
2. **In the PR, the builder says where the code fought the change**: what was worked around,
   special-cased, or written a second time. It goes in the Friction line.
3. **Each night, the retro reads the merges against this section** (`.claude/skills/retro/`):
   a cost out of proportion to the idea, a product concept with no name in the code or with
   two, a decision no test holds, a slower loop. Each becomes a card, which the lead or the
   night builds without the maintainer when it changes nothing they see.
4. **Each month, and before a large feature, the lead reviews the whole codebase** against
   the five points and the top of the board's queue, and cards what the coming work will need.

Getting better at them is a loop: notice what trips the work up when it happens (friction, waste,
a missed chance, anything odd), record it (a PR's Friction line, the conversation), review it on
a schedule (the retro, `.claude/skills/retro/SKILL.md`), make the change at the lowest altitude
that can hold the fix, and check that the fix worked.
