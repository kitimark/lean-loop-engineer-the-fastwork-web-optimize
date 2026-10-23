branch: worktree-wf_11e76b9c-61d-1 (CI branch ci/accent-drawin-width-nolayout)
worktree: .claude/worktrees/wf_11e76b9c-61d-1
last commit: see git log; CI-pushed commit 3c1ab9970 (later local commit only swaps ^= for :is() in the CSS, same elements)
CI runs: 40010696479 (fa6c56c6a, skipped: no [ci:webkit-sim] token, not a dispatch); 40010826238 (3c1ab9970, [ci:webkit-sim] [swap-lane] [swap-fw:accent-nolayout-full]): running. 1 dispatch used of 2.
verified: site tests 6559 pass, check.sh green (slot), Lean StyleDiffAccent builds (full_inRest_nolayout, wkLayoutFrames_values, crLayoutFrames_values), golden regenerated, pre-commit checkmap ok.
open: CI result, ledger row, note section, checks via slot, dry land.
design: flag hero.accent:draw-nolayout-full = draw-nolayout + `transition: none` on .drawingIn (CSS attr nolayout-full); width is set once at draw-in start (1 layout frame per cycle), all other draw frames layout-free in both engines. Look change: headline text jumps instead of gliding.
