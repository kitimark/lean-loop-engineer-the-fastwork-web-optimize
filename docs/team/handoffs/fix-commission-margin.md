# Handoff: fix-commission-margin

Branch `worktree-agent-af15d5794e9baa8d7` (CI ref `ci/fix-commission-margin`), built on `integrate-ports-2` (26e5f53). Read first:
`lean/Fw/Gate/Settle.lean` (section "a node in a skipped subtree is brought into view"), `packages/gate-breakpoints/src/{page,run}.mjs`
(`bringInPage`, `bringSkipped`), `packages/premise-tests/src/tests.mjs` (`prem.cv.skip-flag`, `prem.cv.fresh-after-resize`).

## Finding
- Baseline: gate run 39083482125 (parts=commission, both engines, 3 jobs each, head 26e5f53, no code change): every commission cell
  PASSES, sweeps included. The 86 Chromium / 46 WebKit failures of run 39080214138 (ci/gate-settle ea1433c) and the intermittent
  ones before do not reproduce on the current head; the commission code (60a1d48) is older than all those runs. Cause of the earlier
  failures is not pinned: they were read from a skipped `content-visibility` subtree (rects equal in both arms and consistent with
  margin 132 px, style read 0 px; only at sweep stop 0, intermittent), so (b) measurement artifact is the standing reading, not (a).
- Both arms skip the same ~26 commission nodes per probe (the original also uses content-visibility:auto).

## Lean row (Fw.Gate.Settle)
`Reading`, `view`, `Covered`, `viewCell` + `view_bring`, `viewCell_inert`, `viewCell_notRendered_iff`, `skipped_after_view_only_if_brought`,
`viewCell_fail_of_rendered_diff` (a rendered difference is never hidden), `viewCell_pass_sound`. Golden `gate/settle.jsonl` (+8 `view`
lines); TS twin `settle.mjs view/viewCell`, replayed in `test/settle-golden.test.mjs`.
Premises (Fw.Ops.Premise, 19 now): `cv.skip-flag`, `cv.fresh-after-resize`; golden `ops/premise.jsonl`.

## Gate change (collect only)
`collectInPage` flags a node `skipped:true` when `checkVisibility()` is true and `checkVisibility({contentVisibilityAuto:true})` is false
(read before any rect/style). `run.mjs bringSkipped`: for each non-mount, non-overlay part with a flagged item, scrollIntoView (block
center), settle, collect again, keep the second reading (`view true`); `raw.viewFirst` keeps the first, `raw.viewed` the counts; then
scroll back to the top. `maskNotRendered` (summary.mjs) handles items still skipped. No skipProps or tolerance change.

## Open
- Whether the rule changes any cell is unproven because the baseline passes; CI results of the rule: see the report (runs listed there).
- If a commission cell fails again, compare `raw.viewFirst` with the kept items of that probe: a differing first reading proves (b).
- Lean checks: `sh lean/scripts/check.sh` green; gate-breakpoints `node --test` 110/110; apps/runner premises tests 20/20.
