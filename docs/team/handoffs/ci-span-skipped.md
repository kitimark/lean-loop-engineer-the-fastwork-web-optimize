# ci-span-skipped handoff

State: branch `worktree-wf_04cedea1-d50-1`, worktree `.claude/worktrees/wf_04cedea1-d50-1`; work commits d373695f
(Lean) and 10c55be0 (collector, tests, docs), then a merge of main. No CI runs (the unit needs none).

Verified:
- `Fw.Obs.Timing.fullRun`: a sample is full when not `skipped` and `exit` is 0 or unknown. Non-full samples get no
  verdict (`fullVerdicts`), stay out of windows (`counts`) and out of auto-stage job keys (`jobKeys`).
- Theorems: `timingVerdicts_indep`, `timingVerdicts_same_full`, `judge_indep`, `judge_insert_other`,
  `timingVerdicts_all_full` (old behaviour on all-full input), `fullRun_*`; axiom check 0 failing.
- Golden `packages/contracts/golden/obs/timing.jsonl` regenerated (5 new cases: land dry 2026-10-22, gate-gaps judge,
  run 39722879593 gate-engine 33 s still slow, slow then refusal stays slow, null exit counts as full).
- `Fw.Wire.Obs` decodes `exit` (integer or null) and `skipped`; obs.slow #guards.
- TS: `ciSpans` writes `skipped: true`; `parseSamples` forwards `exit` and `skipped` raw (no TS decision).
- check.sh green; @fw/runner 88 files / 2434 tests; ci-paths 54/54.

Findings (MEASURED, docs/team/tools/timings.md): run 39722879593 chromium gate-engine 33 s is a real outlier (median 21 s),
slow under both rules; the land-dry false alert came from early refusals pooled with full runs.

Open / accepted limits: old lines keep fields (their 0 s skipped samples count until they age out of the window);
a step that exits early with success counts as full; failed runs over a ceiling no longer alert.

Read first: `lean/Fw/Obs/Timing.lean` section "Proofs: full and other samples", then the timings.md section.
