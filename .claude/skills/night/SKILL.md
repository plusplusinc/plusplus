---
name: night
description: The night's whole job, run by the Claude app's scheduled task "plusplus-night" at midnight in the main checkout: read usage, catch up, tally, run the retro, the setup review when due, and the night's cards, then write the digest, whose first line says whether the night ran. Never use it by hand or with the maintainer.
---

Nobody is here to ask, so never ask: a step that can't go on records why and goes to step 8.
`<night>` is `.build/retro/<date +%F>/` in this session's folder, the main checkout, and `<n>`
is `scripts/nightly-tooling.py`. Run each `<n>` command alone, nothing piped or chained. In order:

1. **Begin.** Keep the contents of `.build/retro/last-run`, if any. `<n> begin <night>`.
2. **Read usage.** Load `mcp__ccd_session_mgmt__get_usage` with ToolSearch (`select:` it), call
   it with no arguments, and Write what it returned, as it is, to `<night>/usage.json`, or its
   error if it fails. `<n> usage <night>`; when it exits 1, `<n> outcome <night> failed usage
   "<its line>"` and go to step 8.
3. **Catch up.** `scripts/nightly-retro.sh catch-up <night>`.
4. **Tally.** `<n> tally <night>`.
5. **Retro.** Run the Skill tool with `retro`, args `nightly`, and follow it to its end. When
   `.build/retro/last-run` now differs from step 1's, `<n> outcome <night> ran`; otherwise
   `outcome <night> failed retro "<why, one line>"`.
6. **Review.** `<n> review <night>`. On exit 0, start a `general-purpose` agent in the
   foreground with `model: fable`, told to follow `.claude/skills/review-setup/SKILL.md` with
   `nightly` and to end with its report's one-line summary; then `<n> review-end <night> "<that
   line>"`.
7. **Cards.** Repeat: read usage again as in step 2, without `usage`; `<n> next <night>`. On exit
   1, stop repeating. On exit 0, run the Skill tool with `nightly-card`, args `<card> <worktree>
   <branch>` from its lines, and follow it to its last line; then `<n> decide <night> <card>
   "<that line>"` with a 600000 ms timeout, again while it exits 3 (armed: it waits for the
   merge). An exit of 2 from `next` or `decide`: `<n> outcome <night> failed cards "<its line>"`,
   and stop repeating.
8. **Digest.** `<n> digest <night>`. When its first line says "failed", and only then, load
   `PushNotification` with ToolSearch and send that line after "PlusPlus: ".

Steps 3 and 4 never stop the night: a failed catch-up tops the digest, and the retro reports a
failed tally. Any other step that can't be done runs `outcome <night> failed <step> "<why>"`.
A call the night's guard denies says why: do as it says. After the retro's report, write no text
but a failure's line: `scripts/nightly-retro.sh show` prints that reply.
