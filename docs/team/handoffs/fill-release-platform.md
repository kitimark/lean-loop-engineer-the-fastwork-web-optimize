# fill-release-platform handoff

- Branch `worktree-wf_1e215c74-cb5-1`, worktree `.claude/worktrees/wf_1e215c74-cb5-1`, work commit 92fa6652f, CI trigger e133f74c8, main merged at 5be7ecf19.
- CI runs: chromium-counts 40280497740 (success: base `rewrite` and arm `f1` = platform.entries:fill-release, swipe-touch-v1, 3 runs); lean 40280497901 (success).
- Verified: the tail layer-frames fall 7140 to 6480 (-9.2%), with drawing area -7.7% and tiles -10.9%. Work is noGain in every window (Paint less, RasterTask more). Results are in `results/fill-release-platform/` and the note `research/notes/2026/10-20-fill-release-platform.md`. The ledger row `platform.entries.fill-release` is updated.
- Verified: Lean `Fw.Engine.VisualTimed` and the FillRelease section of `Fw.Parts.PlatformEntries` (same_look for every Env, no_held_after, held_saved, rows_win). The golden `platform-entries-fill.jsonl` is checked by check.sh and by `fill.test.ts` (18 tests).
- Open (lead dispatch):
  - `gh workflow run breakpoint-gate.yml --ref ci/fill-release-platform -f fw=platform.entries:fill-release`
  - `gh workflow run webkit-sim.yml --ref ci/fill-release-platform -f target=rewrite -f vms=3`, then the same with `-f fw=platform.entries:fill-release`. Read with `packages/measure-webkit/src/offscreen-webkit-cli.mjs`.
- TS stand-in: `results/fill-release-platform/layer-frames.mjs` sums the census keys per window. It has no Lean golden.

Conventions: the variant rules sit in `@media (prefers-reduced-motion: no-preference)` at the end of `@layer parts`, one per faithful entry rule. Each selector is the faithful selector plus `.fillRelease` on the stage root. `.order` is included.
Read first: `lean/Fw/Engine/VisualTimed.lean`, then the FillRelease section at the end of `lean/Fw/Parts/PlatformEntries.lean`, then the note.
