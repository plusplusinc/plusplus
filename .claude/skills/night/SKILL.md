---
name: night
description: The night's whole job, run by the Claude app's scheduled task "plusplus-night" at midnight in the main checkout: read usage, catch up, tally, run the retro, write the digest, whose first line says whether the night ran. Never use it by hand or with the maintainer.
---

Nobody is here to ask, so never ask: a step that can't go on records why and goes to step 6.
`<night>` is `.build/retro/<date +%F>/` in this session's folder, the main checkout. In order:

1. **Note the start.** Make `<night>`, and keep the contents of `.build/retro/last-run`, if any.
2. **Read usage.** Load `mcp__ccd_session_mgmt__get_usage` with ToolSearch (`select:` it), call
   it with no arguments, and Write what it returned, as it is, to `<night>/usage.json`, or its
   error if it fails. Run `scripts/nightly-tooling.py usage <night>`. When it exits 1, run
   `scripts/nightly-tooling.py outcome <night> failed usage "<its line>"` and go to step 6.
3. **Catch up.** `scripts/nightly-retro.sh catch-up <night>`.
4. **Tally.** `scripts/nightly-tooling.py tally <night>`.
5. **Retro.** Run the Skill tool with `retro`, args `nightly`, and follow it to its end. When
   `.build/retro/last-run` now differs from step 1's, run `scripts/nightly-tooling.py outcome
   <night> ran`; otherwise `outcome <night> failed retro "<why, one line>"`.
6. **Digest.** `scripts/nightly-tooling.py digest <night>`. When its first line says "failed",
   and only then, load `PushNotification` with ToolSearch and send that line after "PlusPlus: ".

Steps 3 and 4 never stop the night: each writes its own failure where the digest reads it. Any
other step that can't be done runs `outcome <night> failed <step> "<why>"`. End with the
retro's report, or the failure's line, and nothing after: `scripts/nightly-retro.sh show`
prints that reply.
