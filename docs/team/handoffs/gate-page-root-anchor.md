# Handoff gate-page-root-anchor

State: branch worktree-wf_11ac09ad-a60-5 (pushed as ci/gate-page-root-anchor). Measurement run id: 39190672752 (see CI).

Done (PROVED in Lean, wired, tested):
- lean/Fw/Gate/PageRoot.lean: `fits q s := s <= q` (q = requested width, NOT innerWidth: ledger gate.pageRoot.fixedInnerWidth),
  `status` with one theorem per branch (status_missing_left/right, status_na, status_equal_iff, status_differ_iff), cell_pass_iff,
  cell_fail_iff, cell_append_equal (an equal item changes no cell that already compared something), pageRootItems_none /
  addRoot_none / evalStateRoot_none (nothing reported = evalState), evalStateRoot_fail_of_differ, clip_fits, noclip_overflows.
- lean/Fw/Wire/Gate.lean: gate.state reads `viewport.scrollWidth` of each arm and judges with `evalStateRoot` (reply shape unchanged;
  item = box, role pageRoot, key scrollWidth<=requestedWidth, part engine.scroll). 6 guards.
- lean/Fw/Gate/Coverage.lean: the `engine.scroll` wildcard role claim is replaced by one claim per role (scroller, content, pageRoot);
  theorems engine_scroll_no_wildcard, pageRootItems_covered; coverage.jsonl regenerated (26 claims).
- page.mjs records `viewport.scrollWidth`; anchors.json role pageRoot (dims [], count only) + cite; verdict.mjs shows the arms' scrollWidth for
  a failing anchor (a/b); test in packages/gate-breakpoints/test/verdict.test.mjs.

Limits (accepted): the item takes the requested width as the page width; `innerWidth = requested` is not checked here (environment
check `width`, Fw.Measure.Viewport.viewportFaithful, Fw.Faithful.comparable). Requested widths are integers (scope.gen.json), scrollWidth
is an integer; a fractional width would need its own rule. Records without `viewport.scrollWidth` on both arms add no item (older raw
runs keep their verdicts). The item's coverage source is `exempt transcribedEmpiricalOnly` (the clip rule is hand-restated CSS in
apps/site reset.css); count probe of role pageRoot stays uncovered like every count probe. The `compared` count of engine.scroll is +1 in
the summary (expected). TS stand-ins: none (decision is Lean; verdict.mjs only shapes the display value).

Conventions: after a bare lake build run `lake build fwcore`; `pnpm install --offline --frozen-lockfile` first in a fresh worktree.
Read first: lean/Fw/Gate/PageRoot.lean, then the guards at the end of lean/Fw/Wire/Gate.lean.

CI: breakpoint-gate run 39190672752 (dispatch, both engines, head fc222d6b). engine.scroll row pass in every cell, both engines. Raw
records: all 124 probes carry viewport.scrollWidth on both arms; 117 both fit (equal), 7 at width 319 the original is 320 (na, = the 7
excused chromium readings), 0 differ, 0 missing, same in both. Chromium verdict pass. The run is red only by playwright-webkit
"incomplete": matchMedia =Lean | sweep:phone-rotation (#1, #3 not-comparable), not our row; not baselined on main (open item).
