# fill-release-platform handoff

- Branch `worktree-wf_1e215c74-cb5-1`, worktree `.claude/worktrees/wf_1e215c74-cb5-1`, last work commit 92fa6652f (CI trigger e133f74c8).
- CI runs: chromium-counts 40280497740 (queued, ci/fill-release-platform, base `rewrite` + arm `f1` = platform.entries:fill-release, swipe-touch-v1, 3 runs).
- Breakpoint gate and WebKit Simulator arm need lead dispatch (fw input):
  `gh workflow run breakpoint-gate.yml --ref ci/fill-release-platform -f fw=platform.entries:fill-release` and
  `gh workflow run webkit-sim.yml --ref ci/fill-release-platform -f target=rewrite -f vms=3` (base) and the same with
  `-f fw=platform.entries:fill-release` (arm); read with `packages/measure-webkit/src/offscreen-webkit-cli.mjs`.
- Verified: Lean `Fw.Engine.VisualTimed` (phase, fill, Chromium/WebKit held, release_shown, release_saves) and the
  fill-release section of `Fw.Parts.PlatformEntries` (same_look over every Env, no_held_after, held_saved, rows_win);
  golden `packages/contracts/golden/parts/platform-entries-fill.jsonl`; `apps/site/src/parts/platform.entries/fill.test.ts`
  reads every row back from `visuals.module.css` (18 tests pass).
- Open: counts read (offscreen-windows-cli, plus tail layer-frames from census.layers), note
  `research/notes/2026/10-20-fill-release-platform.md`, ledger row update (row appended with status partly-proved),
  merge main, check.sh, dry land, review ready.

Conventions: the variant rules sit in `@media (prefers-reduced-motion: no-preference)` at the end of `@layer parts`, one
per faithful entry rule, selector = faithful + `.fillRelease` on the stage root. `.order` is included.
Read first: `lean/Fw/Engine/VisualTimed.lean`, the FillRelease section at the end of `lean/Fw/Parts/PlatformEntries.lean`.
