# hero-exit-threaded-port handoff

State: branch `worktree-wf_c2c26e40-d7b-1`, CI copy `ci/hero-exit-threaded-port`. Note:
`research/notes/2026/10-2x-hero-exit-threaded.md` (source decision per property, CONFIRMED at WebKit@862f17d).

Built:
- `hero.exit:threaded` (`apps/site/src/parts/hero.exit/threaded.ts`, `threaded.module.css`, `index.tsx`, `part.json`):
  a view timeline on the track (`contain`, linear, `fill: both`); per consumer an opacity/transform/blur animation, only
  accelerated properties.
- Hand-over (Lean `live s fin supported reduced`): the original callback runs until `data-splash` is `done`, the entrance
  has finished (`fin`: the stage's `getAnimations()` all finished, re-read on `animationend`; the phone cue's `copyIn`
  still runs at `done`), the browser has `animation-timeline` and motion is not reduced. Once live, `fin` is not re-read.
- Orbit cards keep the shared unhashed entrance names (`--fw-entrance-names`) in every state, so a bfcache hand-back
  never restarts the entrance. The sentinel has height 0 (pointer cut-off exactly at Lean `sentinelAbove`).
- Lean: section Threaded of `lean/Fw/Parts/HeroExitOpt.lean`; generator `lean/scripts/ExitThreadedGolden.lean`; golden
  `packages/contracts/golden/parts/hero-exit.threaded.jsonl` (24 `live` rows); `threaded.test.ts` checks the TS twin and the CSS.

Verified: site tests, typecheck, `lean/scripts/check.sh`, `fw land --dry` with the allow list in the task.

Writes outside the graph writes: `lean/scripts/check.sh`, `lean/scripts/ExitThreadedGolden.lean`, `lean/Fw/Ci/Trigger.lean`,
`golden/ci/triggers.jsonl`, regenerated `Footprint*.lean`, `footprint*.gen.json`, `golden/preset/v2-proved.decisions.jsonl`.

Open (follow-ups): the harness ready wait (`packages/gate-breakpoints/src/page.mjs` `finiteRunning`) counts scroll-driven
animations as pending (cand arm waits 20 s) and the harness has no sample before that wait, so the entrance window is
covered by Lean and unit tests, not by the probe; gate rule for nodes with an empty rect in every arm; machine-checked
conflict with `hero.countdown:hidden-pause` (reads the inline `--exit-opacity` the hand-over clears); WebKit-lane exit
check; phone replay; preset membership.

Read first: the note, then section Threaded in `HeroExitOpt.lean`, then `threaded.ts`.
