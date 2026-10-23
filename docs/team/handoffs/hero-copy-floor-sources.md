branch: worktree-wf_54d3eb3f-c6d-1 (CI branch ci/hero-copy-floor-sources)
worktree: .claude/worktrees/wf_54d3eb3f-c6d-1
last pushed sha: d6798db66 (lane tag commit; WIP commits before it)
CI runs: path-pix 39971881582 (in progress, 3 sim jobs + 3 chromium jobs); lean 39971882086 (in progress)
second run budget: 1 left (max 2), use only for a capture bug the first run exposes

State
- Lean `lean/Fw/Gate/PathPix.lean` + golden `packages/contracts/golden/gate/path-pix.jsonl`: hook, chainStarts, clockPin, cover, accentGrade with maxY/rows/floorRows. check.sh green.
- Site hook `?fwpin=accent` in `apps/site/src/parts/hero.accent/` (inert when unset, tested). Site tests 6552 pass.
- Lanes (WebKit `pathpix-exit*.mjs`, Chromium `pathpix*.mjs`): hook replaces the DOM swap, Chromium exit mode pins Date.now, cover grid skips occluded cells, change bbox + parts recorded, floor rows in `gradePinned`, scrollY-vs-offset validity.
- Report `packages/measure-webkit/src/pathpix-exit-report.mjs` prints hero_copy per-job per-offset table, summary, where list, pin table.
- Workflow `.github/workflows/path-pix.yml`: sim vm 1-3, chromium run 1-3.

Verified locally: measure-webkit 437, measure-chromium 78, ci-paths tests 54, site 6552.

Open
- Items 1, 3, 5, 6 need the run; item 2 cause unidentified (diagnostics only).
- Outside the write list: path-pix.yml, regenerated footprint.gen.json + FootprintData.lean; Chromium server.mjs and clock-shim untouched (hook via replaceState).
- Note `research/notes/2026/10-2x-hero-copy-floor.md` is written only from report output.

Read first: this file, then `pnpm -s fw ci wait --branch ci/hero-copy-floor-sources --workflow path-pix`.
