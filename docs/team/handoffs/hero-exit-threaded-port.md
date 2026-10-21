# hero-exit-threaded-port handoff

State: branch `worktree-wf_c2c26e40-d7b-1`, CI copy `ci/hero-exit-threaded-port` at cfeae169. Note:
`research/notes/2026/10-2x-hero-exit-threaded.md` (source decision per property, CONFIRMED at WebKit@862f17d).

Built:
- `hero.exit:threaded` (`apps/site/src/parts/hero.exit/threaded.ts`, `threaded.module.css`, `index.tsx`, `part.json`):
  a view timeline on the track (`contain`, linear, `fill: both`); per consumer an opacity/transform/blur animation, only
  accelerated properties (opacity, transform, translate, filter), so no animation sets WebKit's throttle bypass.
- Hand-over: the original callback runs until `data-splash` is `done` in a browser with `animation-timeline` and without
  reduced motion (Lean `live`); then it stops, inline `--exit-opacity` is cleared, `data-exit-live` goes on the track and
  a 1 px span sentinel at 19/20 of the range owns `pointer-events`.
- Lean: section Threaded of `lean/Fw/Parts/HeroExitOpt.lean`; generator `lean/scripts/ExitThreadedGolden.lean`; golden
  `packages/contracts/golden/parts/hero-exit.threaded.jsonl`; `threaded.test.ts` checks the TS twin and the CSS against it.

Verified: site, runner and ci-paths tests, `lean/scripts/check.sh`, `fw land --dry` (with `--allow` for the files below).
Probe run 39652612704 (both engines, verdict run): RED, only on cards not rendered in the band (display:none runs no
animation); every visible node passes. Run 39650676173 failed on the sentinel `div` (anchor `> div`); now a span.

Writes outside the graph writes: `lean/scripts/check.sh`, `lean/scripts/ExitThreadedGolden.lean`, `lean/Fw/Ci/Trigger.lean`,
`golden/ci/triggers.jsonl`, regenerated `Footprint*.lean`, `footprint*.gen.json`, `golden/preset/v2-proved.decisions.jsonl`.

Open: gate rule for non-rendered nodes (lead); the corrected WebKit exit check (scrollY still runs plus a consumer
sample) has no lane yet; phone replay and preset membership. `hero.countdown:hidden-pause` reads the inline
`--exit-opacity` that the hand-over clears (do not combine). Safari before 26.4 runs the animations on the main thread.

Read first: the note, then section Threaded in `HeroExitOpt.lean`, then `threaded.ts`.
