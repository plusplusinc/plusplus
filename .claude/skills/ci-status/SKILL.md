---
name: ci-status
description: Check, diagnose, and rerun PlusPlus CI from a remote (Linux) Claude session — including reading test failures when job logs are unreachable.
---

# CI status and diagnosis from a remote session

The sandbox cannot reach Actions job logs or artifacts (they live on Azure
blob storage, which the network policy blocks with 403 on CONNECT). Use
these paths instead; they are all reachable and need no auth on this
public repo.

## Check state

```bash
# Required checks on a SHA (branch protection needs test + kit-test + cli-test):
curl -s "https://api.github.com/repos/plusplusinc/plusplus/commits/<SHA>/check-runs" \
  | python3 -c "import json,sys; [print(r['name'], r['status'], r['conclusion']) for r in json.load(sys.stdin)['check_runs']]"

# Recent runs on a branch:
curl -s "https://api.github.com/repos/plusplusinc/plusplus/actions/runs?branch=main&per_page=5"
```

## Read failures

The `test` job emits failing-test lines as `::error::` annotations exactly
because logs are unreachable. Fetch them:

```bash
curl -s "https://api.github.com/repos/plusplusinc/plusplus/check-runs/<CHECK_RUN_ID>/annotations"
```

Annotations titled "CI failure detail" carry the grep of xcodebuild.log
(failing test names, Fatal error lines, TEST FAILED). If they're missing,
the failure predates the annotation step or the job died before it ran.

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
