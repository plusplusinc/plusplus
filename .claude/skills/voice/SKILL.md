---
name: voice
description: The PlusPlus brand voice — principles, vocabulary, and rewrite checklist for ALL user-facing copy. Read BEFORE writing or editing any string a user sees (screens, sheets, alerts, buttons, captions, spoken cues, What's-New entries).
---

# The PlusPlus voice

**A sharp tool with a dry sense of humor.** The app speaks like a well-built tool, not a companion: it states facts in short declaratives, gives imperatives in training verbs, and earns trust by being honest about mechanism. Warmth comes from *what* it says (anti-shame content), not *how* (no cheerleading). Reference point: the tagline — "A hackable workout tracker for incrementing yourself".

## Principles

1. **No "we", no "I".** The app has no first person. (Operator is the one deliberate exception — a character with its own persona file; it follows every other rule here.)
2. **The app doesn't refer to itself unless absolutely necessary.** No "the app", no "it/itself" meaning the app. Usually the fix is restructuring so the subject is the user's stuff ("What you have decides what you can train"), not the software. Where self-reference is unavoidable — privacy statements, permission asks — the name is **PlusPlus**: "PlusPlus never phones home."
3. **Consequence first, mechanism second.** Say what it means for the user; explain implementation only where it buys trust (privacy, data ownership). "Your equipment filters the catalog everywhere" is mechanics-first; "What you have decides what you can train" is the same fact, consequence-first.
4. **Deadpan is welcome anywhere it rides a fact.** The test: delete the joke — if information is lost, the line was good; if nothing is lost, the wit was decoration, cut it. Wit must land on first read with no frame required (a line needing a lifter's or a dev's context to parse is out). Anti-shame outranks funny. No jokes on destructive confirms.
5. **Two short sentences beat one long one.** Fragments are house style ("Starts empty. Pick its gear from the catalog."). No em dashes — split the sentence, or use "·".
6. **Anti-shame is voice, not just law.** Every fork with a "lesser" option names it as fully valid ("bodyweight only" is a real answer, not a fallback). No obligation words — "due" is banned. Regressions render neutral.
7. **The ++/git streak is identity, spent sparingly.** Commit/increment vocabulary belongs to identity moments — completion beats, quips, the streak, the tagline, the kit named `main`. The working path speaks plain training English.
8. **Write for anyone training, wink at the dev.** PlusPlus serves lifting, bodyweight, HIIT, and cardio — never assume a barbell or a gym membership on a generic surface. The git layer is a second reading, never load-bearing: every line must land for someone who has never used git.
9. **Training verbs in the working path**: pick, start, build, train, log. "Configure" is correct where the thing genuinely is configuration (a stepper's step size, what a custom exercise measures). Avoid the words that gesture vaguely at software: manage, access ("have access to" is retired — say "have" or "train with"), "settings" as a verb.
10. **Case**: sentence case everywhere; lowercase mono for metadata captions ("jul 17 · 3 items", "edit"); ALL-CAPS only for section headers.

## Vocabulary

| Say | Never | Why |
|---|---|---|
| routine (template) / workout (performed) | mixing the two | #144 |
| have, in your kit | own, have access to | availability, not ownership; access-to is hedge-speak |
| kit (a named equipment set; the default kit is `main`) | library | settled 2026-07-17 |
| equipment (formal: tab names, headers) / gear (spoken: sentences, CTAs) | — | the de facto split, kept deliberate |
| PlusPlus (unavoidable self-reference only) | the app, it/itself | principle 2 |

## Calibration examples

Good (ship-quality, from the app):
- "Starts empty. Pick its gear from the catalog."
- "What you have decides what you can train. Switch sets any time, without touching your history."
- "Logged history keeps its name."
- "PlusPlus never phones home."
- "Nothing logged yet." — the dry fact; its predecessor "Nothing on the bar yet" failed principle 8 (assumes a bar) and principle 4 (needed a lifter's frame).

Bad (the classes the 2026-07-17 sweep removed — don't reintroduce):
- Mechanics-first: "Your equipment filters the catalog everywhere"
- Hedge-question: "What do you have access to?"
- Crammed: "Days or a pace — routines appear here on their day"
- Self-referring: "The app fits itself to what you pick."

## Carve-outs

- **OS-permission copy keeps "access"** — it's Apple's word in grant flows (Health, Calendar, GitHub). "PlusPlus needs calendar access." stays.
- **OperatorPersona.swift** — deliberate first-person character; exempt from principles 1–2 only.
- **FormCues + exercise-specific catalog descriptions** stay specific: a barbell cue SHOULD name the bar. Principle 8 governs generic surfaces only.
- **Bare "—" placeholder glyphs** for missing values are not prose; they stay.
- **"let's go"** (ignition beat) and the RefreshQuips are identity moments, held to principles 4 and 6 but allowed their warmth.

## Rewrite checklist

Before shipping a line: (1) subject is the user's stuff, not the software; (2) consequence first; (3) would deleting the wit lose information; (4) two short sentences, no em dash; (5) lands with zero git/lifting context; (6) vocabulary table honored; (7) no obligation words, lesser options named valid; (8) if a test asserts the old string (SmokeTests), update it in the same PR.
