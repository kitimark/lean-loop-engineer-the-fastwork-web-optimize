# pain-dark-followups handoff (checkpoint 3)

- Branch worktree-wf_27e8c82d-469-1, worktree .claude/worktrees/wf_27e8c82d-469-1, CI branch ci/pain-dark-followups at 9597ea656 (pushed; later commits are local: Lean theorems, part.json, handoff, note).
- CI runs:
  - 39852164349 trajectory-probe push, fw=pain:dark-scroll, verdict run: complete. Item 1: pain-dark cell E (both directions) on Chromium 156 (390, 640) and Linux WebKit 27.2 (390, 640), layer engaged on both engines; flip at the same 4 px row in both arms. Artifacts cells-gpu-chromium, cells-gpu-playwright-webkit-390/-640. Also: premise Hidden FAILS at 390 and 640 (Pain top 398 / 871 px below the card top, 892 needed), so dark-static changes the look (visClass L).
  - 39852250962 breakpoint-gate dispatch, both engines, fw=pain:dark-static: complete, pass.
  - 39852245766 chromium-counts dispatch, swipe-v1 x3, fw=pain:dark-static: complete. Toggle frame invalidation 3,413,963 -> 3,013,203 (same as HOLD), raster tasks 26 -> 20, style recalcs 4 -> 3, +0 layers, whole swipe -0.4 percent area, tiles unchanged (HOLD: -4.0, -6.6 percent).
  - 39852256714 webkit-sim dispatch, fw=pain:dark-static: running.
  - Same-ref comparisons dispatched in background shells (fw run, no nonce read): webkit-sim base and webkit-sim fw=pain:dark-scroll on ci/pain-dark-followups; ids from `gh run list --branch ci/pain-dark-followups`.
- check.sh green at 7b5aab5f0 (before the last Lean theorems; rerun at the final commit). Tests: gate-breakpoints green, ci-paths green, site vitest src/parts/pain green.
- Mechanism: HOLD census (39828605244): base sticky is one backed layer (14.3 MB); HOLD makes the sticky a solid layer and overlap-promotes notes canvas (14.3 MB) and .inner (12.0 MB) above the animated .sticky::before. Base repaints the full 430x775 stage 52 times in y 1500..3000, HOLD 5 times: the WebKit paint saving is the split, not the animation.
- Scratch tools (not committed): scratchpad pain-look.mjs, cmp-counts.mjs, cmp-wk.mjs read the artifacts.
- Open: webkit-sim numbers for dark-static, base and HOLD at the same ref; note/results/ledger rows; check.sh and dry land at the final commit.
