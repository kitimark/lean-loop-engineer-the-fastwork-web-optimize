# fill-release-platform handoff

- Branch `worktree-wf_1e215c74-cb5-1`, worktree `.claude/worktrees/wf_1e215c74-cb5-1`, CI branch `ci/fill-release-platform` at e133f74c8 (all runs below measure that commit). Last work commit: see `git log`.
- CI runs (state when written):
  - chromium-counts 40280497740, success (base `rewrite` vs `platform.entries:fill-release`, swipe-touch-v1, 3 runs).
  - lean 40280497901, success.
  - breakpoint-gate 40282885162 (both engines, fw=platform.entries:fill-release): success, pass. Chromium 7056 readings, 7049 pass/pass, 7 excused not-comparable; playwright-webkit 7056 readings, 6765 pass/pass, 291 excused (unreachable or no vector), 0 FAIL.
  - webkit-sim base 40282962088 (target rewrite, vms 3): running. webkit-sim flag 40282951274 (fw=platform.entries:fill-release, vms 3): running.
- Verified: tail layer-frames fall 7140 to 6480 (-9.2%), drawing area -7.7%, tiles -10.9%; work noGain in every window (Paint less, RasterTask more). Lean `Fw.Engine.VisualTimed` and the FillRelease section of `Fw.Parts.PlatformEntries` (same_look, no_held_after, held_saved, rows_win, webkit_unchanged); golden `platform-entries-fill.jsonl`; `fill.test.ts`.
- Done this round: `results/fill-release-platform/layer-frames.mjs` now sums with `runWindows`/`sumRange` of `packages/measure-chromium/src/offscreen-windows.mjs` (Lean-golden-checked windows); output numbers equal the earlier TS stand-in's.
- Open: read WebKit per zone (`packages/measure-webkit/src/offscreen-webkit-cli.mjs`, minVms 3), memory verdict (cite `Fw.Engine.Resource.verdict`, `budgetB`, `memory_cost_win`, `win_mono_budget`), note, ledger row, merge main, check.sh, dry land, `fw review ready`.
- Fetch results: `pnpm -s fw ci <runId>`; gate tables via `gh run download <id>`.

Conventions: variant rules sit in `@media (prefers-reduced-motion: no-preference)` at the end of `@layer parts`; each selector is the faithful selector plus `.fillRelease` on the stage root; `.order` included.
Read first: `lean/Fw/Engine/VisualTimed.lean`, the FillRelease section of `lean/Fw/Parts/PlatformEntries.lean`, then the note.
