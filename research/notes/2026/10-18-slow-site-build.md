---
id: 2026-10-18-slow-site-build
kind: note
title: "timing.slow on breakpoint-gate site/Build the rewrite (2 s -> 50 s): Lean rebuild inside the site build"
status: draft
created: 2026-10-18
topics: [ci, timing, lake, cache, breakgen, fw-obs-timing]
---

**Answer.** The 26/27/50 s builds are a Lean rebuild, not the Vite build. `pnpm --filter @fw/site build` first runs
`lake exe breakgen --check` (apps/site/scripts/check-breakpoints.mjs:9@aa84eb6), and `BreakgenMain` now also imports
`Fw.Gate.SweepsGen` (lean/BreakgenMain.lean:1-2@aa84eb6, since 35ea874). That pulls Fw.Gate.Scope, Fw.Wire.Gate ->
Fw.Measure.Wire/Fw.Ops.Wire, Fw.Console and Fw.Plan.Core into the site build. The restored Lake entry lacked them,
so 38 modules were built. Cause: a structural closure widening plus a cache whose content depends on which job saved
it. Not a cold pnpm store, no font copy, not runner variance.

## Evidence
| run (branch, commit) | build | Lake entry restored (restore-key) | modules built | Fw.Gate.Scope |
|---|---|---|---|---|
| 39073583410 (integrate-ports-2, fb88aa2) | 2 s | 1d79… (main) | 0 | - |
| 39074271060 (gate-speed-ci, 85cafde) | 26 s | 1d79… (main) | 38 | 18 s |
| 39074514366 (gate-exit-verdict, 9b639bd) | 27 s | 1d79… (main) | 38 | 18 s |
| 39075461722 (integrate-ports-2, 4ef66bc) | 50 s | 7a15… (own branch, fb88aa2 tree) | 38 | 37 s |

- MEASURED (`gh run view --log`, site job): in the 50 s step, `lake` runs 22:44:05 -> 22:44:46 (`[86/86] Built
  breakgen:exe`), then breakgen and Vite take ~8 s (`[aot] built in ~0.9 s`). The 2 s run logs no `Built` line.
- MEASURED: Scope takes 37 s on 4ef66bc vs 18 s elsewhere. INFERRED cause: Scope.lean is +99/-8 lines on
  integrate-ports-2 vs main (`git diff aa84eb6 4ef66bc`; the anchors table now lists every part).
- CONFIRMED (.github/actions/setup-lean/action.yml:43-45@aa84eb6): key = arch + toolchain/manifest + hash of all Lean
  sources. On a miss, restore-keys takes the newest created entry with the same prefix, from this branch or main.
  Keys are immutable; 10 GB limit, LRU (https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching).
- INFERRED (content race): entry 7a15 lacked Scope, Console, Plan.Core etc., although none of them changed between
  fb88aa2 and 4ef66bc (that diff touches only Gate/{Merge,Mount,SweepReduce,SweepsGen}, Plan/{Golden,Workflow},
  Wire/GateDeclared, BreakgenMain, Fw.lean). With `enableArtifactCache` they would have been replayed, so a job with
  a narrower closure saved the entry (a site job building the old 2-module breakgen). Seven workflows race per push.
  The first save wins, and losers log `Failed to save: Unable to reserve cache` (MEASURED in both integrate-ports-2
  breakpoint-gate site jobs).
- MEASURED: on the same commit 4ef66bc, the site build took 9 s in chromium-counts (39075459960) and gate-gaps
  (39075459943). Those jobs started 1-2 min later, after entry aeda… existed. Neither run is in
  .fw-console/timings.jsonl, whose sibling samples all predate 35ea874 (3aedff5..e168f25). The "2.0 s siblings" are
  time-confounded.
- MEASURED: `gh cache list` sums to 12.1 GB (> 10 GB); each ci/* branch saves 380-540 MB Lake entries, so evictions.
## Structural or noise
Structural. Any workflow's site build pays the cost whenever its restored entry was saved by a job that did not
build the new breakgen closure: on every Lean-touching push to a new branch, and whenever a narrow job wins the save
race. The cost scales with Scope's elaboration time, which is growing. The logs differ by 38 rebuilt modules, not by
runner speed.

## Was the Fw.Obs.Timing verdict right?
- `slow` was correct. watch.ts:79@aa84eb6 sends no params, so the defaults apply (n_min 5, N 20, k 3/2, B 30 s,
  stages []). Window [2,1,2,27,26] s: n = 5 and rank90(5) = 5 (Timing.lean:139), so p90 = 27 s. Then 50 > 30 and
  2·50 > 3·27 give `slow` (Timing.lean:214-237). The 27/26 s samples were `noBaseline` (n = 3, 4).
- No structural/noise call was made: with stages = [], `structuralVerdicts` is empty (Timing.lean:338). In the model,
  "structural" means "sets its parallel stage's wall time", not "persists on a branch". Cross-tool siblings are
  separate keys in no Stage.
- Model issue (counterexample, CONFIRMED from the definitions): rank90(n) = n for 1 ≤ n ≤ 9, so p90 = window max, and
  a level shift masks itself. With history [2,1,2,27,26] s, a 40 s run is `ok` (80 ≤ 81) and never alerts. After the
  50 s sample, the same structural 50 s again is `ok`.

## Proposals (not implemented)
1. Narrow the closure. `breakgen` keeps only Fw.Site.BreakpointGen, and a new exe `sweepsgen` (root
   Fw.Gate.SweepsGen) takes `--sweeps` / `--sweeps-golden`. The site build is then back to 2 rarely changed modules,
   about 2 s on any cache state (INFERRED). The `--check` byte gates keep the outputs fixed.
2. One cache writer. Only lean.yml (`lake build`, every default target) saves. Other jobs use `actions/cache/restore`
   (or the target set goes into the key). This also cuts usage against the 10 GB limit.
3. Lean, new lean/Fw/Ops/Cache.lean (import DAG; entry = set of module input hashes;
   $\mathrm{rb}(t,C)=\{m\in\mathrm{cl}(t)\mid h(m)\notin C\}$):
   `rebuild_mono` $\mathrm{cl}(t')\subseteq\mathrm{cl}(t)\Rightarrow\mathrm{rb}(t',C)\subseteq\mathrm{rb}(t,C)$;
   `cache_sound` $\mathrm{save}(k,C_1)\wedge\mathrm{save}(k,C_2)\Rightarrow C_1=C_2$ (violated today);
   `cache_complete` $\forall j$ restoring $k$: $\mathrm{cl}(\mathrm{targets}(j))\subseteq\mathrm{built}(\mathrm{writer}(k))$.
4. Fw.Obs.Timing: use a shift-robust baseline (p50, or p90 of the samples before the first flagged one) plus a
   `shift` verdict (the last m samples all slow against that baseline). Obligation `no_self_mask`: if fewer than half
   the window exceeds t, then p50 ≤ t. Record sibling samples with their commit.

## What this changes in the plan
- §5 Lean strategy (CI Lean builds): add "one Lake cache writer per key, narrow exe closure per consumer" and a task
  `lake-cache-sound` (Fw.Ops.Cache: rebuild_mono, cache_sound, cache_complete) before setup-lean changes.
- timing-alert / Fw.Obs.Timing: add a task for the shift-robust baseline and `shift` verdict (no_self_mask) with
  commit-matched siblings. Today p90 with n ≤ 9 is the max and hides level shifts.
