# timing-small-n (handoff)

**State:** done on branch `worktree-agent-a8ca79a5cddffa6d4` (Lean commit d0f7200, merge of main, docstring fixes on top).
Read first: module doc of `lean/Fw/Obs/Timing.lean`; the input was research note 2026-10-18 slow-site-build (commit 9a5c552).

## What changed
- Baseline is now the nearest-rank **median** (`p50`, rank ⌈n/2⌉), not p90. The reason: with n ≤ 9 the p90 is the window
  max, so a regression seen twice became its own baseline. Slow test is still `d > max(B, k·b)`, defaults unchanged.
- Proved: `site_regression_slow` (40 s after [2,1,2,27,26] s is slow), `site_repeat_slow`, `no_self_mask` (at most
  half the window above t ⇒ slow when k_d·d > k_n·t), `slow_mono_dur`, `slow_mono_window` (a window no slower in
  distribution keeps `slow`), `stable_never_slow` (pairwise within k, n_min ≥ 1, no ceiling breach ⇒ never slow),
  `p50_le_of_few_above`, `le_p50_of_few_below`.
- Structural call: one `StructVerdict` per group of every stage, with `call ∈ {structural, noise, undecided}`
  (`structural_iff`, `noise_iff`, `calls_total`, `calls_given_stages`, `mem_structural`). JSON gains a `"call"` field.
- Stages come from `params.stages`. When there are none (`fw watch` sends no params), `autoStages` builds one stage per
  CI workflow with ≥ 2 job families: job-level CI samples (step without `/`), family = job name up to `" ("`. No TS change
  was needed: the caller stays glue.
- Golden `packages/contracts/golden/obs/timing.jsonl` now has 22 cases, written by `lake env lean --run scripts/TimingGolden.lean`
  (`--check` verifies it). `apps/runner/test/timing-alert.test.ts` replays every case through fwcore (35/35 pass).

## Conventions
- The `$$` math in each docstring was checked by a `checker` against the six-point list. All four findings are fixed.
- I did not touch Fw.Ops.Cache.

## Open items
- `obs.slow` (used by `fw watch`) still returns only slow step names, so the structural call is visible only through `obs.timing`.
  To show it in the alert detail, add it to `slowSteps` in Fw.Obs.Next and to next.ts.
- An auto stage is a whole workflow, which is coarser than its parallel stages (sequential jobs also count as siblings).
  Exact siblings need the start times of the jobs (Span.startMs and runId are already in timings.jsonl) or the `needs:` graph.
- The p90 outlier lemmas (`outlier_bound`, `outlier_shift`) still describe p90. The verdict no longer uses them.
