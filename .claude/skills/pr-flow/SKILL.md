---
name: pr-flow
description: Land a change on plusplus main — the serialized single-branch PR workflow remote sessions must follow (branch protection, squash-only, branch reset after merge).
---

# Landing changes on main

Branch protection (repository ruleset): merges require `test`, `kit-test`,
and `cli-test` to PASS on the head SHA, squash is the only merge method,
and direct pushes to main are blocked. The Claude GitHub App merges via
the MCP (`merge_pull_request`, method squash).

## The loop (remote sessions run everything on ONE designated branch)

1. Develop on the session's designated `claude/...` branch. Commit with
   clear messages; push with `git push -u origin <branch>`.
2. Open a PR (GitHub MCP `create_pull_request`) with `Closes #N` links.
   Check for a PR template first.
3. Wait for required checks on the HEAD SHA (see the ci-status skill).
   Push-triggered runs only; a green dispatch run does not count.
4. Squash-merge via MCP once green.
5. **Reset the branch onto the new main before the next unit of work:**
   ```bash
   git fetch origin main
   git checkout -B <branch> origin/main
   git push --force-with-lease origin <branch>
   ```
   Force-with-lease is safe here only because the branch contains
   exclusively already-merged history.

## Rules that bite

- While a PR is open, do NOT edit files it touches for unrelated work —
  new commits join the open PR. Either finish/merge first or hold changes
  uncommitted (stash) until it lands.
- Pushes to the branch supersede its in-flight CI run (concurrency
  cancellation) — batch pushes when a run's verdict matters.
- If the GitHub MCP is down (token expired), you can still push commits;
  queue merges/comments/issue closes in a scratch file and fire them when
  the connector returns. Never extract git credentials for API calls.
- Issues close via `Closes #N` on merge; use `issue_write` with a
  `state_reason` for manual closes.
