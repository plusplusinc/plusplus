---
name: night
description: The night's whole job, run by the Claude app's scheduled task "plusplus-night" at midnight: read usage, catch up, tally, run the retro, the setup review when due, and the night's cards, then write the digest, whose first line says whether the night ran. Never use it by hand or with the maintainer.
---

Nobody is here to ask, so never ask: a step that can't go on records why and goes to step 8.
This session sits in a worktree of its own, where a card is built, but the night's files are
the main checkout's: `scripts/nightly-tooling.py night` prints `<night>`, its
`.build/retro/<date>/`, then `<n>`, its `scripts/nightly-tooling.py`. Run each `<n>` command
alone, nothing piped or chained: past 7:45 the guard passes only such a call. In order:

1. **Begin.** Keep what `scripts/conversations.py --last-run` prints. `<n> begin <night>`.
2. **Read usage.** Load `mcp__ccd_session_mgmt__get_usage` with ToolSearch (`select:` it), call
   it with no arguments, and Write what it returned, as it is, or its error, to `.build/usage.json`
   in this session's folder. `<n> usage <night> <that file>`; when it exits 1, `<n> outcome
   <night> failed usage "<its line>"` and go to step 8.
3. **Catch up.** `scripts/nightly-retro.sh catch-up <night>`.
4. **Tally.** `<n> tally <night>`.
5. **Retro.** Run the Skill tool with `retro`, args `nightly`, and follow it to its end. When
   `--last-run` now prints other than at step 1, `<n> outcome <night> ran`; otherwise
   `outcome <night> failed retro "<why, one line>"`.
6. **Review.** `<n> review <night>`. On exit 0, start a `general-purpose` agent in the
   foreground with `model: fable`, told to follow `.claude/skills/review-setup/SKILL.md` with
   `nightly` and to end with its report's one-line summary; Write that line to
   `.build/last-line.txt` in this session's folder, then `<n> review-end <night> <that file>`.
   On exit 2, `<n> outcome <night> failed review "<its line>"`.
7. **Cards.** Repeat: read usage again as in step 2, its exit 1 ending the repeat and recording
   nothing (the night ran); `<n> next <night>`.
   - Exit 0: run the Skill tool with `nightly-card`, args `<card> <worktree> <branch>` from its
     lines, to its last line; Write that line to the `last-line` file it printed, then `<n>
     decide <night> <card> <that file>` with a 600000 ms timeout, again while it exits 3 (armed,
     waiting for the merge).
   - Exit 1: stop repeating.
   - Exit 2 from `next` or `decide`: `<n> outcome <night> failed cards "<its line>"`, and stop.
8. **Digest.** `<n> digest <night>`. When its first line says "failed", and only then, load
   `PushNotification` with ToolSearch and send that line after "PlusPlus: ".

Steps 3 and 4 never stop the night: a failed catch-up tops the digest, and the retro reports a
failed tally. Any other step that can't be done runs `outcome <night> failed <step> "<why>"`.
A call the night's guard denies says why: do as it says. After the retro's report, write no text
but a failure's line: `scripts/nightly-retro.sh show` prints that reply.
