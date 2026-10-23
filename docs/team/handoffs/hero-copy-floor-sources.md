branch: worktree-wf_54d3eb3f-c6d-1 (CI branch ci/hero-copy-floor-sources)
worktree: .claude/worktrees/wf_54d3eb3f-c6d-1
last commit sha: 49f34ca20 (main merged; CI run pushed at f16ee6ff6); dry land VERDICT dry hero-copy-floor-sources; review ready: review
CI runs: path-pix 39971881582 (complete, success, round 0); path-pix 39985824264 (complete, success, round 1, sha f16ee6ff6, 3 sim + 3 chromium jobs)
second run budget: spent (2 of 2 runs used)
note: research/notes/2026/10-2x-hero-copy-floor.md regenerated from run 39985824264 (pathpix-exit-report.mjs); tests and check.sh green

State
- Lean `lean/Fw/Gate/PathPix.lean` + golden `packages/contracts/golden/gate/path-pix.jsonl`: hook, chainStarts, clockPin, cover, accentGrade with maxY/rows/floorRows. check.sh green.
- Site hook `?fwpin=accent` in `apps/site/src/parts/hero.accent/` (inert when unset, tested). Site tests 6552 pass.
- Lanes (WebKit `pathpix-exit*.mjs`, Chromium `pathpix*.mjs`): hook replaces the DOM swap, Chromium exit mode pins Date.now, cover grid skips occluded cells, change bbox + parts recorded, floor rows in `gradePinned`, scrollY-vs-offset validity.
- Report `packages/measure-webkit/src/pathpix-exit-report.mjs` prints hero_copy per-job per-offset table, summary, where list, shared-pixel table, pin table.
- Round 1: Lean ownership rule (`foreignMasks`, `countedIn`): hero_copy does not count pixels inside another graded layer mask (WebKit deck-card corners); lSource fix; outside-mask bbox.
- Workflow `.github/workflows/path-pix.yml`: sim vm 1-3, chromium run 1-3.

Verified: measure-webkit 474, measure-chromium 78, ci-paths 56, land-inputs 56, check.sh green (round 1); site 6552 (unchanged since round 0).

Open
- WebKit deck-card corner variation: cause INFERRED (Core Animation clip, GraphicsLayerCA.cpp:3218-3262@862f17d), masked by ownership rule, not pinned.
- Follow-up for the user look review: Chromium P differs from A at rest (offset 0) by 426 px, delta 13 (273 at delta 1 in hero_copy, 153 at delta 13 in deck masks): class look-change.
- path-pix.yml, FootprintData.lean, footprint.gen.json are in the writes since graph r352; Chromium server.mjs and clock-shim untouched (hook via replaceState).
- Note `research/notes/2026/10-2x-hero-copy-floor.md` is written only from report output.

Read first: this file, then `pnpm -s fw ci wait --branch ci/hero-copy-floor-sources --workflow path-pix`.
