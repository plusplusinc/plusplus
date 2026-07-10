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
2. Develop, commit, push with `git push -u origin claude/<slug>`. Review
   any non-trivial diff before pushing, composed from two layers: the
   swift-reviewer agent (this repo's proven bug classes) plus the built-in
   `/code-review` at high effort (general correctness, wider net). Neither
   subsumes the other. For repo-wide audits or overnight bug hunts, prefer
   a dynamic workflow ("use a workflow to … and adversarially verify each
   finding") over hand-spawned parallel agents — the orchestration is
   deterministic and the session stays responsive.
3. Open a PR (GitHub MCP `create_pull_request`) with `Closes #N` links;
   check for a PR template first. Subscribe with `subscribe_pr_activity`
   — comments and CI *failures* arrive as events, but CI success, new
   pushes, and merge conflicts never do.
4. **Arm a merge watcher immediately** (Dave, 2026-07-09: "merge as soon
   as they're ready"; auto-merge is deliberately OFF — he wants the agent
   in the loop on every merge). Background Bash (`run_in_background`)
   that polls the head SHA's check-runs every ~30 s and EXITS when
   `test`+`kit-test`+`cli-test` are all terminal — the exit notification
   is your merge signal; merge in that same turn. Watcher hygiene, both
   learned the hard way: keep the script dead simple (a heredoc-fed
   `python3 -` combined with a `<<<` herestring silently feeds python the
   wrong stdin — one watcher hung forever on this), and emit on EVERY
   terminal state, never just success. Keep a long fallback wakeup
   (~30 min) armed while any watcher runs; a buggy watcher is silent.
5. Wait for required checks on the HEAD SHA (see the ci-status skill).
   Push-triggered runs only; a green dispatch run does not count — and
   **dispatching ci.yml on a branch CANCELS its in-flight push run** via
   the concurrency group (so does any push), leaving the ruleset staring
   at cancelled required checks. Never dispatch or push on a branch whose
   push run you're waiting on; if it happens, `rerun_workflow_run` the
   cancelled PUSH run (the MCP tool — the raw REST rerun is
   proxy-blocked) rather than dispatching a duplicate.
6. Squash-merge via MCP the moment the watcher reports green;
   unsubscribe. The remote branch can be deleted after merge (note: ref
   deletion via git push is proxy-blocked; leave cleanup to the branch
   sweep, #52).

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
