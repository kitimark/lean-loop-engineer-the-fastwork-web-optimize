Branch: worktree-wf_1a1544e3-bc5-1 (CI branch ci/morph-idle-chromium-rebaseline). Worktree: .claude/worktrees/wf_1a1544e3-bc5-1
Last commit: see git log (started from f3248e954).
CI runs (chromium-counts dispatched by `pnpm -s fw run`, swipe-v1, runs=3, target rewrite, sha f3248e9):
- 39936881473 base (no flag), in progress
- 39937184249 flag (fw=morph.columns:idle-none), in progress
Verified: nothing yet. Open: both runs; delta and sign; note append; land dry.
Note: the two arms are separate workflow runs, each builds the image from the same sources (the workflow has an image_run input, but `fw run` does not send it).
Read first: research/notes/2026/10-20-morph-idle-none.md (last sections).
