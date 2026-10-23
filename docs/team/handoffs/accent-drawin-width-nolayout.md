branch: worktree-wf_11e76b9c-61d-1 (CI branch ci/accent-drawin-width-nolayout)
worktree: .claude/worktrees/wf_11e76b9c-61d-1
last commit: fa6c56c6a (pushed to ci/accent-drawin-width-nolayout)
CI runs: webkit-sim push run of fa6c56c6a ([swap-lane] [swap-fw:accent-nolayout-full]): id pending (look up with pnpm -s fw ci wait --branch ci/accent-drawin-width-nolayout --workflow webkit-sim). 1 of 2 dispatches used.
verified: Lean StyleDiffAccent builds (full_inRest_nolayout, wkLayoutFrames_values, crLayoutFrames_values), golden regenerated, pre-commit checkmap ok.
open: CI result, ledger row, note section, checks via slot, dry land.
design: flag hero.accent:draw-nolayout-full = draw-nolayout + `transition: none` on .drawingIn (CSS attr nolayout-full); width is set once at draw-in start (1 layout frame per cycle), all other draw frames layout-free in both engines. Look change: headline text jumps instead of gliding.
