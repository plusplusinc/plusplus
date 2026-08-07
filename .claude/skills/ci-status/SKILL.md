---
name: ci-status
description: Check, diagnose, and rerun PlusPlus CI from a remote (Linux) Claude session — including reading test failures when job logs are unreachable.
---

# CI status and diagnosis from a remote session

The sandbox cannot reach Actions **artifacts** (they live on Azure blob
storage, which the network policy blocks — a `curl` of the download URL dies
on CONNECT). Job **logs** it CAN reach, through the GitHub MCP rather than
`curl`:

```
mcp__github__get_job_logs  { job_id, return_content: true, tail_lines: 200 }
```

⚠️ That corrects a claim this skill carried until 2026-07-30, which sent
several sessions hunting for evidence they already had access to. The check
run's id IS the job id, so `.../commits/<SHA>/check-runs` → `id` feeds
straight in. `tail_lines` defaults to 500 and the log runs to thousands, so
ask for the tail you need — the failure summary is at the end.

The paths below are all reachable and need no auth on this public repo.

## Check state

```bash
# Required checks on a SHA (branch protection needs test + kit-test + cli-test):
curl -s "https://api.github.com/repos/plusplusinc/plusplus/commits/<SHA>/check-runs" \
  | python3 -c "import json,sys; [print(r['name'], r['status'], r['conclusion']) for r in json.load(sys.stdin)['check_runs']]"

# Recent runs on a branch:
curl -s "https://api.github.com/repos/plusplusinc/plusplus/actions/runs?branch=main&per_page=5"
```

⚠️ **`kit-test` can fail for a non-Swift reason**: its first step is the agent-doc size
budget (2026-07-28; per-rules-file cap 2026-07-31) — **25 KB** on CLAUDE.md, **24 KB** per
`.claude/rules/*.md` file, and a **~2 KB line-length cap** on CLAUDE.md and every rules
file. It rides an already-required job so the budget binds without a branch-protection
change. `docs/DECISIONS.md` is deliberately exempt: it is append-only and its long entries
are the record, not drift.

Annotations read `CLAUDE.md too large`, `<rules file> too large`, or `Line too long in
<file>`. For an oversized rules file, split it by path scope (narrower `paths:`
frontmatter) or move history to docs/DECISIONS.md — don't raise the cap. Otherwise the fix is to move
detail into docs/DECISIONS.md (dated entry) or a path-scoped rules file, and to add a NEW
line rather than grow an existing one — **never to raise the limit**. Swift never ran in that
case, so don't go hunting a test failure. The line cap is not only about merge conflicts: the
8.7 KB paragraph it caught in `app-surfaces.md` had also drifted into stating things that
were no longer true, which a rules file auto-loads into every app session.

## Read failures

The `test` job emits failing-test lines as `::error::` annotations exactly
because logs are unreachable. Fetch them:

```bash
curl -s "https://api.github.com/repos/plusplusinc/plusplus/check-runs/<CHECK_RUN_ID>/annotations"
```

Annotations titled "CI failure detail" carry the grep of xcodebuild.log
(failing test names, Fatal error lines, TEST FAILED). If they're missing,
the failure predates the annotation step or the job died before it ran.

## ⚠️ ui-test is not required, so check it deliberately

`test`, `kit-test` and `cli-test` gate main. `ui-test` does not — and a
non-required check can sit red for weeks without anyone noticing. It was red
on every push to main from 2026-07-24 to 2026-07-30 (22 of them, and two
TestFlight builds) while the required three went green every time (#483).

Since 2026-07-30 a red `ui-test` on **main** files one tracking issue titled
"ui-test is red on main" and then stays quiet until that issue is closed, so
the state reaches the backlog exactly once instead of never. **An open issue
with that title means the suite is currently red** — a later red push adds
nothing, by design.

⚠️ **That "by design" is a real blind spot, and it has cost six days once**
(2026-08-07). The alarm is keyed on "is anything red", not on WHICH tests, so
a NEW failure arriving while the issue is open is silent. #500 was filed
2026-07-31 for two tests; #532 turned Today's whole timeline blank on
2026-08-01 and its four failures were never reported, through twelve merges
and a TestFlight build. **So when you touch a surface the smoke suite covers,
read the failing SET from the latest main run yourself** (`get_job_logs`,
`tail_lines: 160` — the `::error::` lines are at the end) rather than
inferring "already known" from the open issue. And when you fix the suite,
CLOSE #500, or the next regression is invisible too.

Making it required was considered and rejected: it is the slowest job and has
two documented flake modes below, so one bad runner would block every merge.

## Known flake modes (check before suspecting code)

- **ui-test wedge**: `app.launch()` hangs on a runner simulator
  (DebuggerLLDB errors, killed at 45 min). Cancel + re-dispatch once.
- **Historic parallel-test corruption** (fixed 2026-07-08): in-memory
  SwiftData containers shared state across containers even when uniquely
  named. Test containers must use unique on-disk temp-file stores — see
  the CLAUDE.md Patterns block before writing any new test container.

## Rerun

Rerun via the GitHub MCP (`actions_run_trigger`, method `rerun_failed_jobs`
with the run_id). A cancelled or failed REQUIRED check blocks merge until a
push-triggered run passes — `workflow_dispatch` runs do NOT satisfy the
ruleset even on the same SHA.

## Watch without polling the conversation

Run an until-loop in a background Bash task (never foreground sleep):
poll the check-runs endpoint every 60 s, break on completion, print a
final DONE line with conclusions.

## Did the TestFlight build actually make it?

A green `testflight.yml` run only proves the binary was DELIVERED to App
Store Connect. ASC then processes it asynchronously (→ appears in TestFlight,
or gets rejected with an email to the Apple ID) — invisible to that run. To
see the ASC side, dispatch the **`asc-status.yml`** workflow (GitHub MCP
`actions_run_trigger`, `run_workflow`, `ref: main`): it mints a JWT from the
ASC key and prints each recent build's `processingState` (PROCESSING / VALID /
INVALID / FAILED), annotating INVALID/FAILED ones. Read it with
`get_job_logs`. `manageAppVersionAndBuildNumber` is off, so the build number is
whatever the Archive step stamped (`CURRENT_PROJECT_VERSION=run_number`) — a
duplicate would be rejected at processing time, showing as a build that never
appears despite a green run.
