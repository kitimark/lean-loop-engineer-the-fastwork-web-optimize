# fill-release-platform handoff

- State: done, waiting for review. Branch `worktree-wf_1e215c74-cb5-1`, worktree `.claude/worktrees/wf_1e215c74-cb5-1`, CI branch `ci/fill-release-platform` at e133f74c8 (every run below measures that commit).
- CI runs:
  - chromium-counts 40280497740 success (base `rewrite` vs flag, swipe-touch-v1, 3 runs); lean 40280497901 success.
  - breakpoint-gate 40282885162 success, pass on both engines (Chromium 7049 of 7056 pass, 7 excused; Playwright WebKit 6765 pass, 291 excused, 0 FAIL).
  - webkit-sim flag 40282951274 success, 3 VMs. webkit-sim base 40282962088 failed: VMs r1 and r3 hit the 2100 s determinism bound; only r2 is good, so every per-zone cell reads undecided (n=1+3 VMs).
  - webkit-sim base retry 40305413688 (same commit and inputs) failed: r1 good, r2 and r3 lost in Determinism sessions (host overload, wk-sim-hang). Reader (offscreen-webkit-cli.mjs, Lean minVms 3): every zone (z4500, z5000, finish, whole) undecided, n=1+3 VMs. Pooling: the reader takes the VM id from the dir name r<k> and Lean has no commit field, so pooling is possible only when ids differ; retry r1 + first-run r2 gives n=2+3, still undecided. Follow-up: WebKit recount after wk-sim-hang lands. Accepted limit.
- Verified: tail layer-frames 7140 to 6480 (-9.2%), drawing area -7.7%, tiles -10.9%, work noGain in every window (Paint less, RasterTask more). WebKit census layers and backing memory equal in base (r2) and flag at every stop (149.3 and 105.8 MB), as `webkit_unchanged` predicts.
- Lean: `Fw.Engine.VisualTimed`; FillRelease and MemoryTrade sections of `lean/Fw/Parts/PlatformEntries.lean` (memoryWin_fits, memoryWin_neutral, work_change_not_memoryWin over `Resource.verdict` with `budgetB`); check.sh green after merging main; site, runner, ci-paths tests pass.
- Memory verdict: Chromium no-win (memory down, RasterTask up, not a memory-only win); WebKit no-win (no change). `layer-frames.mjs` now uses the golden-checked `runWindows`/`sumRange`.
- Main merged (faded-pause, morph-end-nobounce): conflicts only in `lean/Fw/Ci/Trigger.lean` (both golden lists kept) and `packages/contracts/golden/ci/triggers.jsonl` (regenerated with `lake test -- --write-ci-trigger-golden`). Ledger: webkit field, missingWhy, next and a notes entry updated. The lead added the four files to the graph writes (r516).

Conventions: variant rules sit in `@media (prefers-reduced-motion: no-preference)` at the end of `@layer parts`; each selector is the faithful selector plus `.fillRelease` on the stage root; `.order` included.
Read first: `lean/Fw/Engine/VisualTimed.lean`, the FillRelease section of `lean/Fw/Parts/PlatformEntries.lean`, then the note `research/notes/2026/10-20-fill-release-platform.md`.
