# pain-dark-followups handoff (checkpoint 2, runs in flight)

- Branch worktree-wf_27e8c82d-469-1, worktree .claude/worktrees/wf_27e8c82d-469-1, CI branch ci/pain-dark-followups at 9597ea656 (pushed). Later commits only touch this handoff, the note, results, ledger.
- CI runs (all running or queued at this write):
  - 39852164349 trajectory-probe push, fw=pain:dark-scroll, verdict run (item 1: pain-dark cell Chromium + Linux WebKit 390/640 in artifacts cells-gpu-chromium, cells-gpu-playwright-webkit-390/-640)
  - 39852250962 breakpoint-gate dispatch, both engines, fw=pain:dark-static (item 3)
  - 39852245766 chromium-counts dispatch, swipe-v1 x3, fw=pain:dark-static (item 3)
  - 39852256714 webkit-sim dispatch, fw=pain:dark-static (item 3); compare with HOLD 39828605244 and base 39818734599 (older commit; a same-ref base and HOLD webkit-sim are planned if the spread needs it)
- Built (commit 5a8e834b5): Lean `PainDarkScroll.lean` (chromium_* tie of the toggle frame; ToggleUi and RideEveryFrame labelled model assumptions; layer budget backingKpx / hold_backing / static_eq_base; static_pixel_eq with premise Hidden; ownsFlip golden rows); variant `pain:dark-static` (no animated layer, pseudo-elements dark from the start); painScan reads flag-layer opacity and section visibility; trajectory-probe.yml walks the pain cell with the push search (Chromium) and on Linux WebKit legs 390 and 640 (`--only pain`).
- Mechanism found in the HOLD webkit-sim 39828605244 census: base has the sticky stage as ONE backed layer (14.27 MB, positionSticky); HOLD makes the sticky a solid layer and promotes notes canvas (14.27 MB) and `.inner` (12.0 MB) by overlap above the animated `.sticky::before`; base repaints a full 430x775 layer every 50 px step in the pinned band (51 paints between y 1500 and 3000) while HOLD repaints it twice. So the paint saving may come from the split, not from the animation: dark-static tests that.
- Open: read the four runs; Hidden measured rows from the probe raw (pTop - top >= vh + 47.5); note/results/ledger update; check.sh; tests; dry land.
