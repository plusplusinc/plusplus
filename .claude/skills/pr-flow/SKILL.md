---
name: pr-flow
description: Land a change on plusplus main — the parallel feature-branch PR workflow (branch protection, squash-only, one branch per unit of work, concurrent PRs).
---

# Landing changes on main

Branch protection (repository ruleset): merges require `test`, `kit-test`,
and `cli-test` to PASS on the head SHA, squash is the only merge method,
and direct pushes to main are blocked. The Claude GitHub App merges via
the MCP (`merge_pull_request`, method squash).

Work is PARALLEL by default (Dave, 2026-07-09: "I authorize you to make
however many branches you need, and parallelize work"). One branch per
unit of work; PRs open and run CI concurrently; nothing queues behind an
open PR's checks.

## The loop (per unit of work)

1. Branch off fresh main: `git fetch origin main && git checkout -b
   claude/<slug> origin/main`. Pick a slug that names the change
   (`claude/equipment-exercises`), not the session. ci.yml triggers on
   every `claude/**` push.
2. Develop, commit, push with `git push -u origin claude/<slug>`. Run the
   swift-reviewer agent on any non-trivial diff before pushing.
3. Open a PR (GitHub MCP `create_pull_request`) with `Closes #N` links;
   check for a PR template first. Subscribe with `subscribe_pr_activity`
   — comments and CI *failures* arrive as events, but CI success, new
   pushes, and merge conflicts never do, so poll status before merging.
4. Wait for required checks on the HEAD SHA (see the ci-status skill).
   Push-triggered runs only; a green dispatch run does not count.
5. Squash-merge via MCP once green; unsubscribe. The remote branch can be
   deleted after merge.

## Parallel rules

- **One unit of work per branch, always.** Never stack a second feature
  on a branch whose PR is open — new commits join that PR. Start the next
  branch from `origin/main`, not from another feature branch.
- **Same-file overlap is allowed but ordered.** If two in-flight branches
  touch the same file, the second to merge rebases mechanically:
  `git fetch origin main && git rebase origin/main` then
  `git push --force-with-lease`. Force-with-lease is safe only on
  `claude/*` branches you created this session.
- **One local working tree.** Commit (or stash) before switching
  branches; never let one branch's edits bleed into another's commit. For
  genuinely simultaneous edits, `git worktree add` a second checkout.
- Pushes to the SAME branch supersede its in-flight CI run (concurrency
  cancellation) — batch pushes when a run's verdict matters. Different
  branches run CI independently; fan out freely.
- A merged PR is finished. Follow-up work = new branch off new main,
  new PR; never reuse merged history.

## Rules that bite

- If the GitHub MCP is down (token expired), you can still push commits;
  queue merges/comments/issue closes in a scratch file and fire them when
  the connector returns. Never extract git credentials for API calls.
- Issues close via `Closes #N` on merge; use `issue_write` with a
  `state_reason` for manual closes.
- The ui-test job is not required by the ruleset but IS the smoke layer —
  dispatch it on a branch when a PR touches flows it covers.
