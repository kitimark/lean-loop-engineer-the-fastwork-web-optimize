# Handoff: fix-commission-margin

Branch `worktree-agent-af15d5794e9baa8d7` (CI ref `ci/fix-commission-margin`), on `integrate-ports-2` (26e5f53) + main 74d2595.
Read first: `lean/Fw/Gate/Settle.lean` (section "brought into view"), `packages/gate-breakpoints/src/{page,run}.mjs`
(`bringInPage`, `bringSkipped`, `VIEW_ON`), `packages/premise-tests/src/tests.mjs` (`prem.cv.skip-flag`, `prem.cv.fresh-after-resize`).

## Finding
- Baseline gate run 39083482125 (parts=commission, both engines, 3 jobs each, head 26e5f53, no change): every commission cell PASSES,
  sweeps included. The 86/46 cells of run 39080214138 do not reproduce; the commission code (60a1d48) predates all those runs.
- (a) real difference is excluded: premises hold on CI, both engines (run 39084127865): after a resize, a skipped subtree brought
  into view has the fresh margin, style = geometry = (W-40-300)/2 (cv.fresh-after-resize); the flag rule is detectable (cv.skip-flag).
  Only the known cv.auto-margin finding is red. (b) artifact stays the reading of the old failures but is unproven (no repro).
- Both arms skip the same ~26 commission nodes per probe (the original also uses content-visibility:auto).

## Lean row (Fw.Gate.Settle)
`Reading`, `view`, `Covered`, `viewCell` + `view_bring`, `viewCell_inert`, `viewCell_notRendered_iff`, `skipped_after_view_only_if_brought`,
`viewCell_fail_of_rendered_diff` (a rendered difference is never hidden), `viewCell_pass_sound`. Golden `gate/settle.jsonl` (+8 `view`
lines), TS twin `settle.mjs view/viewCell` (replayed in `test/settle-golden.test.mjs`). Premises (registry 20): the two above.

## Gate change, OFF by default (`FW_GATE_VIEW=1`)
`collectInPage` flags `skipped:true` (checkVisibility vs contentVisibilityAuto, read before any rect/style); `bringSkipped` scrolls the
part into view, settles, re-collects, keeps the second reading (`raw.viewFirst`, `raw.viewed`). Probes only: in sweeps the bring starts
commission animations for all later stops (run 39084163586: 111/114 samples unsettled, job > 29 min). Run 39086375181 (probes): Chromium
all pass; WebKit 7 probes FAIL on scroll-driven `--commission-shrink` (0.4746 vs 0.3702): scrollY differs per arm. So default = baseline.

## Open
- To switch it on: a scroll position equal by construction, or exclude scroll-driven props from the second reading.
- If a commission cell fails again on the baseline, rerun with FW_GATE_VIEW=1 and compare `raw.viewFirst` with the kept items.
- CI used 5 runs (over the 4 allowed: one full push run was cancelled). `lean/scripts/check.sh` green; gate-breakpoints 110/110.
