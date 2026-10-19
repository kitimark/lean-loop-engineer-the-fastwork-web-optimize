# Handoff gate-page-root-anchor (fix round 1)

State: branch worktree-wf_11ac09ad-a60-5 (pushed as ci/gate-page-root-anchor for the measurement run 39190672752 at the older head).
Fix round 1 is unpushed: no new dispatch; the numbers below are recomputed from that run's raw records.

Done (PROVED in Lean, wired, tested):
- lean/Fw/Gate/PageRoot.lean: `viewportOf q := ceil q` (the viewport the engines give, engines.mjs:37-38: 600.5 -> 601) and
  `fits q s := s <= viewportOf q`. Theorems: fits_iff, le_viewportOf, viewportOf_int (whole widths judged as before),
  fits_fractional_example, fits_of_le; per-branch status theorems (status_missing_left/right, status_na, status_equal_iff,
  status_differ_iff), cell_pass_iff, cell_fail_iff, cell_append_equal, pageRootItems_none/_some, addRoot_none, evalStateRoot_none,
  evalStateRoot_fail_of_differ, clip_fits, noclip_overflows, noclip_fits_of_le (all against `viewportOf q`). #guards: 600.5 -> 601.
- evalStateRoot LaTeX states compared' recomputed from the new part table Pi' (not carried over from evalState).
- lean/Fw/Wire/Gate.lean: gate.state reads each arm's `viewport.scrollWidth`, judges with `evalStateRoot`; 2 new guards (600.5 with 601 pass, 602 fail).
- Coverage.lean: one claim per role of engine.scroll (no wildcard); coverage.jsonl is current (`--check` exit 0).
- page.mjs records `viewport.scrollWidth`; anchors.json role pageRoot + cites say ceil(requested); verdict.mjs shows the arms' scrollWidth;
  verdict.test.mjs has a fractional case.

CI (run 39190672752, breakpoint-gate dispatch, head fc222d6b; recomputed with the new item from the merged raw records of both engines):
- old item (s <= q): 117 equal, na 7 = 3 at 319 (min-width 320) + 4 fractional (viewport rounded up), 0 differ, 0 missing.
- new item (s <= ceil q): 121 equal, na 3 (the 319 probes: the original is 320 wide by min-width 320), 0 differ, 0 missing; same on chromium and playwright-webkit.
- engine.scroll row: pass in every reachable cell; webkit hover-pointer-cross and fractional-gaps UNREACHABLE (environment not achieved).
- The run is red only by playwright-webkit "incomplete": matchMedia =Lean | sweep:phone-rotation (not our row; open item, not baselined on main).

Accepted limits: `innerWidth = requested (rounded)` is not checked by this item (environment check width, Fw.Faithful.comparable).
The 14 new pageRoot count probes (role pageRoot, key count, one per breakpoint class) are uncovered in `fw coverage`, and the anchor item itself is not enumerated by
`allProbes` (it is added by evalStateRoot, outside roleKeys); making allProbes emit it is more than a one-line change, so it is a follow-up.
Records without `viewport.scrollWidth` on both arms add no item. TS stand-ins: none (verdict.mjs shapes the display value only).

Conventions: after a bare lake build run `lake build fwcore`; `pnpm install --offline --frozen-lockfile` first in a fresh worktree.
Read first: lean/Fw/Gate/PageRoot.lean, then the guards at the end of lean/Fw/Wire/Gate.lean.
