import Foundation

/// The "repo that explains itself" layer (#148): `plusplus init` drops a
/// CLAUDE.md and three skills into every training repo so any Claude that
/// can see the repo — Claude Code, claude.ai via the GitHub connector —
/// becomes a training assistant with zero hosting.
///
/// The skill bodies are mirrored in `claude-plugin/skills/` in the app
/// repo (the plugin install path); edit both when either changes.
enum ClaudeScaffold {
    static var files: [(path: String, data: Data)] {
        [
            ("CLAUDE.md", Data(claudeMD.utf8)),
            (".claude/skills/weekly-review/SKILL.md", Data(weeklyReview.utf8)),
            (".claude/skills/tweak-program/SKILL.md", Data(tweakProgram.utf8)),
            (".claude/skills/deload-check/SKILL.md", Data(deloadCheck.utf8)),
        ]
    }

    private static let claudeMD = """
    # This is a PlusPlus training repo

    Versioned training data for [PlusPlus](https://github.com/plusplusinc/plusplus),
    stored as deterministic JSON (interchange schema v1). You — a Claude
    reading this — can act as a training assistant here: review progress,
    answer questions from history, and propose program changes.

    ## Layout

    ```
    program/exercises/           one exercise per file — the movement catalog
    program/routines/            one routine template per file — groups, sets, targets
    program/equipment/           gear with config worth keeping (weight steps, metric profiles)
    program/equipment-libraries/ one gear list per training spot (Home, Hotel…)
    history/YYYY/                finished sessions — append-only, NEVER edited
    .claude/skills/              /weekly-review, /tweak-program, /deload-check
    ```

    ## Rules

    - **History is the record.** Never create, edit, rename, or delete
      anything under `history/`. The app and CLI append; nothing rewrites.
    - **Program edits are proposals.** Change `program/` files on a fresh
      branch and lint before committing — or better, use the
      `propose_program_change` MCP tool, which does branch + lint + rollback
      for you and never pushes. A human reviews and merges.
    - **The codec is deterministic.** Sorted keys, stable whitespace — write
      complete documents and don't fight the formatting; `plusplus lint`
      is the arbiter.
    - **Names are identity.** Renaming an exercise starts a new identity;
      history stays with the old name. Warn before renaming.
    - **Rep ranges shift.** `reps`/`repsUpper` express "15–20"; adjust by
      moving the whole range.
    - **Weights don't convert.** The optional bundle `units` field (lb/kg)
      is a declaration, not a conversion — stored numbers never change.

    ## Tools

    With the [plusplus CLI](https://github.com/plusplusinc/plusplus) on PATH:

    - `plusplus lint` — validate the repo against the schema
    - `plusplus stats [--json]` — per-exercise aggregates
    - `plusplus export` / `import` — interchange bundles
    - `plusplus mcp` — stdio MCP server over this repo: `list_exercises`,
      `list_routines`, `get_history`, `stats`, `lint`, and the fenced
      `propose_program_change`

    ## Voice

    Quiet terminal: lowercase mono for data, sentence case for prose.
    Anti-shame is an invariant — celebrate increments (`+5 lb`, `++`) and
    presence; report misses as neutral data or not at all.
    """

    private static let weeklyReview = """
    ---
    name: weekly-review
    description: Summarize the last week of training from a PlusPlus workout repo — sessions, per-exercise increments, and streak. Use when the user asks how their training week went, wants a weekly review, or asks what changed since last week.
    ---

    # Weekly review

    Summarize the last ~7 days of training from this repo's history, in
    PlusPlus's quiet-terminal voice: lowercase monospace for data, sentence
    case for prose.

    ## Getting the data

    Prefer the MCP tools if the `plusplus` server is connected: `get_history`
    (newest first; every set carries targets and actuals) and `stats`
    (per-exercise aggregates). Without MCP, read the files directly: sessions
    live under `history/YYYY/` as one JSON file per finished session
    (append-only), routine templates under `program/routines/`.

    ## What to report

    1. **Sessions this week** — one line each: `date · routine · sets · duration`.
    2. **Increments (++)** — per exercise, compare this week's best completed
       set against the previous appearance of that exercise in history.
       Weight up beats reps up when both moved. Format deltas like the app:
       `+5 lb`, `+2 reps`, `new` for a first appearance, `=` for holding steady.
    3. **Streak** — consecutive weeks (ending this week) with at least one
       session. One number with context: `4 weeks running`.
    4. **The week ahead** — if routines under `program/` imply a cadence the
       user mentioned, note what's likely next. Skip this if you'd be guessing.

    ## Framing rules (non-negotiable)

    - Anti-shame is a design invariant. Celebrate increments and presence.
      Regressions and missed days are reported as neutral data or not at
      all — never with failure language ("only", "just", "you missed",
      "fell short").
    - Holding a weight steady IS a result. `=` is not a problem to fix.
    - Never invent numbers. If history is empty or thin, say what's there and
      stop. A one-session week gets the same respect as a five-session week.
    """

    private static let tweakProgram = """
    ---
    name: tweak-program
    description: Propose a change to the training program (add/adjust exercises, sets, targets, routines) as a reviewable git branch — never a direct edit. Use when the user wants to modify their program, add an exercise, change weights/reps, or restructure a routine.
    ---

    # Tweak the program

    Program changes are proposals, not edits: they land on a fresh git
    branch, gated by lint, and a human merges them. History is the record
    and is never touched.

    ## How to apply a change

    With the `plusplus` MCP server connected, use `propose_program_change`:

    - `files`: full interchange-JSON content for each changed file, paths
      under `program/` only (`program/exercises/<slug>.json`,
      `program/routines/<slug>.json`).
    - The tool commits to a NEW branch, runs lint, and rolls the whole thing
      back if lint fails. It never pushes — tell the user the branch name and
      let them review, push, and merge.
    - The repo needs a clean work tree; if the tool refuses, say why instead
      of working around it.

    Without MCP (e.g. claude.ai reading the repo, or a plain shell): make the
    same change by hand on a new branch and run `plusplus lint` before
    committing. Same rules — `program/` only, small reviewable diffs, the
    human merges.

    ## Change hygiene

    - Read the current file first (`list_exercises` / `list_routines` or the
      file itself); write back the complete document, not a fragment. The
      codec is deterministic — don't fight its key order or whitespace by
      hand-editing.
    - One concern per proposal: "bump bench and add a back-off set" is one
      proposal; "bump bench and also reorganize leg day" is two.
    - Renaming an exercise creates a NEW identity — history and "last time"
      stay with the old name. Warn before doing it; prefer editing everything
      except the name.
    - Respect rep-range semantics: `reps`/`repsUpper` express "15–20"; shift
      the whole range rather than collapsing it.
    - Explain the why in the commit message: the reasoning is the review.

    ## Never

    - Write under `history/` (append-only, owned by the app and CLI).
    - Commit to the current branch or push anywhere.
    - Delete an exercise that history references without flagging it — files
      may be adopted back by sync, and history that points at it keeps
      working, but the user should know.
    """

    private static let deloadCheck = """
    ---
    name: deload-check
    description: Analyze training history for progression stalls and recommend a deload or target adjustment. Use when the user feels stuck, asks whether to deload, or wants a plateau check on an exercise.
    ---

    # Deload check

    Read-only analysis: find where progression has stalled and say what you'd
    change. Applying any change goes through `/tweak-program` (branch +
    lint), never directly from here.

    ## Detecting a stall

    Use `stats` for the per-exercise shape and `get_history` for the
    set-level detail (or read `history/YYYY/` files directly without MCP).
    For each exercise with enough data, look at the last 3–5 appearances:

    - **Stalled**: same top weight AND same-or-fewer reps across 3+ sessions.
    - **Grinding**: weight held but actual reps sliding below target, or
      logged sets shrinking session over session.
    - **Progressing**: weight or reps moved anywhere in the window — not a
      candidate, say so and move on.

    Fewer than 3 appearances is "not enough signal", not a stall.

    ## What to recommend

    - A classic deload: cut the working weight ~10% (round to the equipment's
      step — 5 lb plates, 2.5 for microplate gear) and rebuild over 2–3
      sessions.
    - Or a volume cut (one fewer set) when reps are grinding but weight is
      moving.
    - Or a target adjustment: if the rep range is never reached at the
      current weight, propose the range the last month actually supports.
    - Name the exercise, the evidence (dates + numbers), and the single
      change you'd make. Offer to hand it to `/tweak-program` as a proposal.

    ## Framing rules (non-negotiable)

    - Anti-shame: a deload is a strategy, not a setback. Never "you failed to
      progress" — the data says "this weight is fully adapted; drop to
      reload."
    - Don't pathologize normal variance: one flat session is noise. Three is
      a pattern.
    - If nothing is stalled, say so plainly and celebrate what's moving.
    """
}
