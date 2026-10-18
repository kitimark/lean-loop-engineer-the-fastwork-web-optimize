# WebKit lane: aligning original (A) and rewrite (R) by scroll position (step-align)

Status of claims below: MEASURED = CI run 39053799594 (webkit-sim, target both, 3 VMs, branch ci/step-align, commit e0fa48c);
CONFIRMED = read in code or proved in Lean.

## Cause of 74 vs 107 steps

- MEASURED: both arms run the same schedule, y = 0, 50, 100 ... up to their own maxY = scrollHeight - innerHeight (viewport
  430x775, dpr 3), 50 px per step, the last step at maxY. Original: docH 6042 (6043 on one VM), maxY 5267, 107 steps. Rewrite
  (placeholder build, default config): docH 4378, maxY 3603, 74 steps. Same on all three VMs of each arm.
- So the step count follows the page height (the placeholder rewrite is 1664 px shorter). It is not a harness bug, not a step
  size and not an end condition, and it will change again every time the rewrite grows. Forcing the same count (for example
  clamping A to 74 steps) would measure a different part of A and hide the difference; padding R is not possible.
- Chromium compares by position for the same reason (zones y00000 ...); WebKit now does the same.

## Design (Lean first)

- `lean/Fw/Measure/StepAlign.lean`: a step is keyed by (previous y, y, next y). Two steps of A and B are the same piece of
  trajectory when the keys are equal; `pairedSteps A B` are the steps of A whose key occurs in B. Zones are floor(y / h)
  (h = 500) as before; `align` gives per zone: steps of each side, paired steps, the A and B sums over the paired steps (all
  12 count types plus paint area), the delta A - B and `full` (zone has steps, both sides have the same number of them, and all
  of them are paired, so A and B sums cover the same trajectory).
- Proved (docstrings carry the LaTeX): pairing is symmetric in what it keeps (swap), a run against itself pairs everything and
  every zone is full with delta 0, zone sums partition the paired sums (nothing is lost or counted twice), the delta total is
  the difference of the totals, paired steps are a sublist of the run. mathview lint: 0 failing.
- Wire op `measure.webkit.align` (`Fw/Measure/Wire.lean`), 7 golden cases in
  `packages/contracts/golden/measure/measure.webkit.align.jsonl`; fwcore reproduces them (`test/align.test.mjs`).
- JS is glue: `packages/measure-webkit/src/align.mjs` (request builder, tables, `classifyAligned` = the existing `classify` with
  TOL.zone over the full zones), CLI `align <a.json> <r.json>` and `align-classes <a1> <r1> ...`.
- The schedule itself is unchanged (no change to `scrollrun.mjs`).

## CI: rewrite arm in webkit-sim

`.github/workflows/webkit-sim.yml`: `target` original | rewrite | both. A `site` job builds apps/site (default config) and
the rewrite jobs (r1.., `--site`) serve it; originals stay v1.. with unchanged file names; `align` job (Linux, fwcore artifact)
pairs vN/rN per session and writes `webkit-align`. Preset and fw overrides are still refused by the plan job.

## Result (MEASURED, 3 VMs x 2 passes per arm, run 39053799594, jobs on separate VMs)

- Structure: 72 paired steps of A 107 / R 74 in every one of the 6 passes. Full zones (500 px): y0 = 0, 500, ... 3000 (7 zones,
  70 steps), identical in all passes. Zone 3500 is partial (A 10 steps, R 4, 2 paired). Zones 4000-5000 exist only in A.
  The last step of each run (its own maxY) never pairs because the next offset differs.
- Counts over the 7 full zones (sum, min - max over the 6 passes):

| count type | A | R | A - R | class of A / R / delta (per-zone cells, tol zone) |
|---|---|---|---|---|
| RecalculateStyles | 443 - 475 | 138 - 155 | 289 - 323 | quarantined all |
| Layout | 443 - 478 | 147 - 185 | 288 - 325 | quarantined all |
| Paint | 885 - 977 | 169 - 206 | 714 - 798 | quarantined all |
| Composite | 139 | 139 | 0 | deterministic all |
| RenderingFrame | 0 | 0 | 0 | deterministic all |
| EventDispatch | 70 | 140 | -70 | deterministic all |
| FireAnimationFrame | 489 - 503 | 279 | 210 - 224 | A and delta quarantined, R deterministic |
| ObserverCallback | 81 - 99 | 0 | 81 - 99 | A and delta quarantined, R deterministic |
| FunctionCall | 667 - 719 | 351 - 361 | 316 - 368 | A, delta quarantined; R stable |

  Reading: A and R are now comparable per zone. What is deterministic (Composite, EventDispatch) can be compared cell by
  cell; the style, layout and paint counts move run to run in WebKit (the quiet-mode work, webkit-quiet) and cannot be
  used per zone until that is settled. EventDispatch is 1 per step in A and 2 per step in R (INFERRED: the rewrite
  registers a second scroll listener or dispatches one more event; not investigated here).
- Classes are over 6 passes from 3 VMs (kMax 4, tMax 24 policy applies to frames; zone rows use TOL.zone as in `determinism`).

## merge across VMs: rows paired by key (Lean)

- MEASURED (run 39053799594): `merge` over the three original VMs failed with "sessions do not have the same rows": VM v2 had
  document height 6043 (maxY 5268, and 5263 in pass 2 of its census), the others 5267, so the census row labels differ
  (`census|layerCount|y=5268` against `y=5267`). The label uses the measured offset, so page-height-dependent labels differ between VMs.
- Fix: rows are matched by key, not by position. Lean `StepAlign.pairedRows` (keys of the first session that every session has) and
  `unpairedRows` (keys some session lacks, each once, with the number of sessions that have it); fwcore op
  `measure.webkit.pairRows`, 6 goldens. Proved: `mem_pairedRows`, `mem_unpairedRows`, `pair_cover` (a key is paired or unpaired,
  never both, never lost), `unpairedRows_count` (1 <= n < sessions), `pair_self`.
- Glue `src/mergerows.mjs`; `cli.mjs merge` prints the table of paired rows (worse class wins) and then the unpaired rows with
  "k of n sessions" and Lean's reason; `--out` adds `unpaired`. It never crashes on differing labels and never drops silently.
  Consequence: when one VM is 1 px taller, the end-of-page census state is excluded (y=5267 in 2 of 3, y=5268 in 1 of 3).
- Test: `test/mergerows.test.mjs` (fixture with the y=5268 VM). The `merge` job now needs the fwcore artifact.

- CI (MEASURED): run 39081148105 (target both, 2 VMs, commit 9e5641c) passed end to end: plan, site, fwcore, sim v1 v2 r1 r2,
  align (including `align-classes`, first CI run of that step) and merge, 106 table rows, no unpaired rows (both original VMs had the
  same document height). The pairing of differing labels is covered by `test/mergerows.test.mjs` and the goldens, not by this run.
- Earlier attempts of the same branch: sim jobs failed on `simctl list devices ETIMEDOUT`, on a stalled seek after the first scroll
  (v1, twice; the watchdog from webkit-green reports it) and, in the first attempt, on the within-VM table step that now needs fwcore
  (moved to the merge job). A `gh run rerun --failed` loses the rerun job's artifact (the first attempt's partial artifact of the same
  name stays), so a verdict needs a fresh dispatch.

## Found on the way (not fixed, not mine)

- The seek stage after the first scroll of VM v1 stalled twice for 12 minutes (watchdog limit); not investigated here.

## Reproduce

`gh workflow run webkit-sim.yml --ref ci/step-align -f target=both -f vms=3`, then `gh run download <id>` and
`node packages/measure-webkit/src/cli.mjs align-classes v1-session-1.json r1-session-1.json ...`.
