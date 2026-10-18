# page-root-clip handoff

State: branch worktree-wf_3b41e65f-bce-1 (base integrate-ports-4 faa66f6a), pushed as ci/page-root-clip.

Done
- lean/Fw/Measure/Viewport.lean: viewportFaithful (Size w h), theorems refuses_iff, accepts_self, refuses_width,
  refuses_height, accepts_iff; op measure.viewport in Measure/Wire.lean; golden
  packages/contracts/golden/measure/measure.viewport.jsonl (name follows the measure.<op> convention).
- packages/measure-chromium/src/viewport.mjs: TS twin (container has no Lean), checked against the golden and fwcore in
  test/viewport.test.mjs. run.mjs throws after the geometry read when the page reports another size; meta records
  innerWidthPx, innerHeightPx, scrollWidthPx, visualViewportScale.
- apps/site: div[data-fw=page-root] around main with the original rule (2.gBuqKVzi.css:1 .start-selling: min-width
  320px, direction ltr, background #f5f5f3, overflow-x clip), in styles/reset.css; morph.columns stage is fixed,
  opacity 0, pointer-events none (out of flow like the original panel at morph 0).

Verified (MEASURED, CI runs 39140970481 swipe-v1, 39140973547 swipe-touch-v1, both target both, all jobs ran, pass)
- R and A: innerWidth 430, innerHeight 932, scrollWidth 430, scale 1, docHeight 5558, maxScroll 4626 (r1 files).
- Touch run scrolls to maxY 4626 (531 frames), same as the original.

Open
- Gate anchor for page-root (scrollWidth <= innerWidth) not added: needs Lean gate tables, outside this task's writes.
- PL5 verdict and WebKit are not re-run here (faithful-checks). Extra 96 px clamp not investigated; docHeight now equal.
- check.sh run on a dirty tree; land --dry stale until integrate-ports-4 lands.
