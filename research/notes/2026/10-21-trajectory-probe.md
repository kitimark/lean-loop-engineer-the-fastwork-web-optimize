---
id: 2026-10-21-trajectory-probe
kind: note
title: "Trajectory probe round 2: arm identity, coverage, baseline, and what CI measured for bugs A, B and C"
status: final
created: 2026-10-20
authors: [agent:measure-engineer]
topics: [measurement, trajectory-probe, webkit, gate]
---

# Trajectory probe round 2 (2026-10-20)

Round 1 measured the rewrite with its flags off (`research/notes/2026/10-21-measure-probe-review.md`). Round 2 makes that
impossible to repeat and re-measures. Tool doc: `docs/team/tools/trajectory-probe.md`.

## What changed (all decided in Lean, `lean/Fw/Gate/Trajectory.lean`; golden `packages/contracts/golden/gate/trajectory.jsonl`)

- **Arm identity.** Every arm records its config hash and `fwMode`. Allowlist: rewrite = the search's hash, non-empty, `hydrate`;
  original = no `window.__fw`. Else `refused:config` (exit 2, no verdict). It caught a bug of mine at once: the faithful arm was
  served the variant server, whose flagged HTML client-renders for the default search; it now has its own server.
- **Coverage is a verdict.** Empty bucket 1-9 in a push, missing morph value, `beyond` window: `fail:coverage`.
- **Baseline per unit.** Faithful rewrite vs original gives `new / both / cleared / ok` for each unit; red iff some unit is new.
- **Read timing.** `t0`/`t1` around the reads; p50/p90 of read cost and frame gap per arm and phase (Lean `quantile`).
- **Reps.** The morph path is walked 3 times and pooled (added after the first CI round, below).
- **Apple witness.** Job `probe-apple`: Playwright WebKit 27.2 on macos-26, hero path only, max-parallel 1.

## Runs

All arms of every run passed the identity check (24 or 48 arms per Linux job; 12 on macOS): each rewrite arm had the hash of its
search and `hydrate`. "Pre" = one pass of the morph path (ff592d6b), "reps" = three passes pooled (f19913eb / e85d995e).

| id | case | commit | run |
|---|---|---|---|
| a | default config | pre ff592d6b | 39405218882 |
| a | default config | reps f19913eb | 39409003529 |
| b | `?preset=v2-proved` (8 flags: preset-drop-waapi is on main) | reps f19913eb | 39415671864 |
| c | `?fw=morph.tween:waapi` | reps f19913eb | 39412301221 |
| d | `?fw=hero.exit:scoped` (Linux both engines + macos-26) | pre ff592d6b | 39407166794 |
| d | `?fw=hero.exit:scoped` (Linux both engines + macos-26) | reps e85d995e | 39419128841 |

## Verdicts (units new against the faithful arm, content only; coverage-new in brackets)

Reps runs; bug A units are hero copy, cards, cta, countdown; bug B units are nav classes and the logo in the morph; bug C is
`nav.cls.is-on-dark` at 390.

| run | engine | A hero copy+cards | B nav classes + logo | C is-on-dark 390 |
|---|---|---|---|---|
| a default | Chromium | 0 | 0 [14] | both 2 (baseline red) |
| a default | Linux WebKit | 0 | 1 [14] | both 13 |
| b v2-proved | Chromium | 0 | 0 [14] | both 2 |
| b v2-proved | Linux WebKit | 0 | 4 [42] | both 13 |
| c waapi | Chromium | 0 | 0 [0] | both 2 |
| c waapi | Linux WebKit | 0 | 1 [181] | both 12 |
| d scoped | Chromium | 0 | 0 | both 2 |
| d scoped | Linux WebKit | **228 new** (all 4 widths) | 0 [28] | both 15 |
| d scoped | macos-26 WebKit | **187 new**, 57 both | not walked (hero only) | not walked |

The pre-reps d run says the same for A: macos-26 241 new (of 330 failing), Linux WebKit 416 new (mostly A), Chromium 0.

Reading the table:

- **Bug A (CONFIRMED by measurement):** `hero.exit:scoped` fails exactly where it was reported: WebKit only, on macos-26 and on
  Linux, 4 widths, in `hero.copy.opacity/transform/rect`, `hero.cta.rect`, `hero.countdown.unit.rect` and `hero.deck.card.*`
  (steps s25..mid onward, reason `apart`). Chromium has none. The default config and the 8-flag preset have none.
- **Bug C (CONFIRMED, baseline):** `is-on-dark` at 390 fails in the faithful arm too (steps `a0`, `open-hold@10`), so it shows as
  `both`, never `new`, in all five Linux runs, as predicted.
- **Bug B (NOT witnessed, unpredicted):** `morph.tween:waapi` shows no new nav class or logo unit in Chromium (0 content, 0
  coverage) and none in Linux WebKit beyond what the default config shows. The probe does not reproduce what the user saw. The
  four WebKit close@0 units in run b (v2-proved has no waapi) show the same first-sample flicker. Next step (not done): record
  `document.getAnimations().length` per sample to see whether the waapi driver runs at all in the headless wheel push; check
  that the repro needs a real compositor or a touch drag (touch input is a follow-up).

## Findings that were not predicted

1. **Round-1 coverage was frame-phase noise.** With one pass the default config (cand and faithful are the same site) scored
   126 new coverage units in Chromium (a single empty bucket fails every unit that shares it, ~42 units). Three pooled passes gave
   42 in runs a and b (one bucket at 390 each), 0 in runs c and d. Lane RED from coverage alone is not evidence; the content-new groups are.
   Not tuned away: coverage stays a verdict, the summary shows content and coverage apart.
2. **Linux WebKit cannot measure the morph push.** Frame gaps are p50 140-200 ms (p90 400-600 ms), the tween passes a tenth in
   about one frame (INFERRED from the Chromium counts), so 2000+ units fail coverage in the faithful arm as well (baseline `both`). Its hero path is measurable.
3. **Reads do not dominate** (MEASURED): Chromium read 0.4 ms vs gap 17 ms; Linux WebKit read 1 ms vs gap 150 ms; macOS hero read
   1 ms (p90 3). So the lean read set was not needed and not run on CI; the slow frame is the engine's, not the probe's.
4. **The faithful rewrite is baseline red on macOS in 57 hero units** (steps `mid`, `hold`, `b25`, mostly rects of track, stage,
   deck, cue). Linux WebKit shows 0 `both` in the hero path. Not investigated; it needs its own task.
5. `close@0` and approach steps (`a*`) flicker in the morph path (nav.background-color, earn.opacity); a group counts only when it
   repeats across widths or runs.

## Limits and follow-ups

Not a gate stage and no preset reads it. Touch input, the WebKit 325900 engine-premise test, stale anchor exclusions and Mobile
Safari in the iOS Simulator are follow-ups. One run per case; the A result repeats across two commits and two engines, the B
non-result across three runs. TS stand-ins: the kit's in-page reads and `reduce.mjs` (checked against the Lean golden).

Writes outside the task's graph writes: `lean/Fw/Store/Layout.lean`, `lean/Fw/Wire/Store.lean`, `lean/Fw/Store/Golden.lean`,
`lean/Fw/Ops/LakeJobsGen.lean`, `lean/scripts/check.sh`, `packages/contracts/golden/store/trajectory.jsonl`,
`packages/contracts/src/artifacts.ts` (the `fw run --trajectory` dispatch and the lean job, from round 1).
