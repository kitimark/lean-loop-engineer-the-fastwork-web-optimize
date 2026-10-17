# Handoff: zone-baselines-webkit (measure-engineer)

State: branch `ci/zone-baselines-webkit` (worktree branch), commit trailer `Task: zone-baselines-webkit`. CI run 39061324429 (webkit-sim,
vms=3, sessions=1; v2, v3 green, v1 step timed out at 50 min AFTER writing its session json, merge skipped; v1 json used).
Done: `results/baselines/webkit/original.{zones,baseline}.json` (6 runs = 3 VMs x 2 passes, 11 zones, detDrift and detDriftTotals empty);
note `research/notes/2026/10-17-zone-baselines-webkit.md` (table per type: class, drift, noise band, gate yes/no).
Code: `packages/measure-webkit/src/zone-baseline.mjs` (glue; Lean does `measure.webkit.zones` + `measure.zoneBaseline`, twice: zone-level
and whole-run class table), test `test/zone-baseline.test.mjs` (needs fwcore).

Learned
- Gateable per zone: RenderingFrame (constant 0), Composite (2/step), EventDispatch (1/step): all set by the scroll script, a weak gate.
  The 10 others (RecalculateStyles, Layout, Paint, FireAnimationFrame, TimerFire, ObserverCallback, FunctionCall, ScheduleStyleRecalculation,
  InvalidateLayout, paintArea) are model-check-only; the file keeps lo/hi/base as a noise band.
- The zoneBaseline op takes one class table per call; WebKit classes differ by level, so the glue calls it with the zone table (zones) and the
  total table (totals).
- gh run download needs `-R kitimark/lean-loop-engineer-the-fastwork-web-optimize` outside a git dir; worktree needs FWCORE or the main
  checkout's lean build (handoff.mjs finds it).

Open
- The class table is from earlier runs; regenerate/refreeze (`merge --out`) then re-run `zone-baseline.mjs` (test fails while stale).
- The v1 job hang after the session write is unexplained (not diagnosed); a 4th VM/session would widen the baseline but can only worsen the table.
- No rewrite arm: this lane serves the original only.
Read first: the note above.
