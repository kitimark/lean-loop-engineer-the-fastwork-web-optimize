# smoothness-probe

Question: are the transitions of the original and of the rewrite equally smooth? Two parts, because "smooth" has two meanings.

| part | asks | data | decided by |
| --- | --- | --- | --- |
| A, continuity | does the value follow the driver (scroll position, morph value) without stalls, jumps, reversals or a late tail? | trajectory-probe raw readings, any run | Lean `Fw.Gate.Smooth` (`metrics`), TS twin `src/smooth/reduce.mjs` |
| B, cadence | do frames arrive evenly in real time while a scripted wheel scroll runs? | in-page rAF intervals (and Chromium's frame trace) on a CI runner | Lean `Fw.Gate.Smooth` (`verdict` on the rate, `hitchVerdict` on per-repeat hitch counts, `across` over job samples), same twin |

## Files
- Lean: `lean/Fw/Gate/Smooth.lean` (definitions, theorems, golden section), `lean/scripts/SmoothGolden.lean`, golden `packages/contracts/golden/gate/smooth.jsonl` (checked by `lean/scripts/check.sh`, job "smooth golden check").
- TS twin: `packages/gate-breakpoints/src/smooth/reduce.mjs`; `test/smooth.test.mjs` replays the golden.
- Part A glue (TS stand-in, not golden-checked): `extract.mjs` builds the pushes and the two ideal curves from a raw trajectory artifact, `table.mjs` groups per engine, width, window, ideal and arm and keeps per-node (property) medians, ranges and run ids; its `differences` rule (an arm's median outside the other arm's min-max over runs) only picks cells to read, it decides nothing; `cli.mjs continuity`.
- Part B glue: `launch.mjs` (Chromium with real wheel and `browser.startTracing`), `cadence.mjs` (the scripted windows and the run), `trace.mjs` (counts from a frame trace, for the page's compositor sink only: the renderer pid with most `BeginMainThreadFrame`, its layer tree with most `DrawFrame`; a fixed uncapped slow-event table; descriptive, never in the verdict), `cadence-table.mjs` (`cli.mjs cadence`; groups job samples, calls the Lean twin `across`).
- CI: `.github/workflows/smoothness.yml`, lane token `[ci:smoothness]`; candidate and widths come from the `[trajectory preset=... widths=...]` line (empty widths = 390 and 1280).

## Rules
- Part A, two ideals. `line`: the straight line in the driver between the settled ends; easing counts as a defect in every arm alike, so only differences between arms mean anything. `ref`: the original's own response at the same driver value (leave-one-out for the original). Stall, jump, reversal and tail thresholds are Lean constants (`stallPm`, `jumpPm`, `reversePm`).
- Part B, a bad frame is a gap above 34 ms between rAF callbacks (`badTenths` 340). An arm's rate is bad frames per frame pooled over its repeats. The A/A spread is the larger of the gap between the base and aa arms and the spread of repeats inside either. An arm is smoother only when its rate plus the spread is under the other's (`judge`); fewer than 5 repeats in any of the four arms is `insufficient`.
- Part B, the hitch rule: a hitch is a frame over 60 ms (`hitchTenths` 600). Per repeat the hitch count; `hitchVerdict` says an arm is smoother only when every repeat of the other arm has more hitches than every repeat of this one, and only when the A/A pair is not itself told apart. It exists because the rate rule is coarse: at 390 px hero one frame is about 0.58 points, the whole effect.
- Across job samples: `across` with `agreeNeeded n` = ceil(2n/3): `first` when at least that many samples say first and none says second (and the other way), else `same`; under 3 samples `insufficient`. The note's "how sure" column is this.
- The verdict reads main-thread rAF cadence. The trace's presented and dropped frames (compositor, page sink only) are reported beside it and never enter it.
- Windows: `hero` is a wheel burst of 60 events x 42 px every 16 ms from the top (about 2520 px); `end` is the end-of-page morph (approach, rest, one wheel push open, one close, 1 s hold each). Per repeat every arm opens a fresh page; arms are interleaved and the order rotates.
- Arms: `orig`, `base` (faithful rewrite), `aa` (the same faithful rewrite on a second server), `cand` (the pushed search). Verdict pairs: orig vs base, base vs cand, orig vs cand, each against the base/aa spread.

## Limits
- Linux runner, software rendering at 60 Hz vsync: the numbers rank arms, they are not phone times. The A/A pair bounds the runner noise.
- Chromium only. Linux WebKit renders about 150 ms frames in software (its cadence would be the runner's), and a macOS leg needs a row in `Fw.Ci.Pool.Caps` with a measured p90, which this task does not own.
- WebKit: original-vs-rewrite continuity exists only for the end window; macOS WebKit hero has no original rows, Linux WebKit is skipped.
- Tracing slows the page, so traced repeats are reported apart and never enter the verdict.
- A running rAF loop keeps the main thread producing frames at every vsync; it does the same to all arms.

## Use
- Run: push `ci/<task>` with a commit message that carries `[ci:smoothness]` and optionally `[trajectory preset=v2-proved widths=390,1280]`. The trajectory-probe mark rule (a width subset needs `diagnostic`) does not apply here: the workflow passes `LANE=smoothness` to `trajectory-line.mjs`, and Lean `Fw.Ci.Trigger.parseLine_smoothness` proves this lane reads a line exactly as before that rule.
- Legs: two widths x three sets; each set is its own job (artifact `smoothness-<width>-<set>`), so one run gives three independent noise samples per width. Traced repeats per arm: 5 (`TRACE_REPS`). Hitches (gaps over 60 ms) are listed with scroll position and the browser's long animation frames; descriptive only.
- Tables from downloaded runs: `gh run download <runId> -D <dir>/<runId> -p 'smoothness-*'`, then `node packages/gate-breakpoints/src/smooth/cli.mjs cadence --runs <dir> --out <out>`; part A: `... continuity --runs <dir> --out <out> --engines chromium,macos-webkit --widths 390,1280`.
