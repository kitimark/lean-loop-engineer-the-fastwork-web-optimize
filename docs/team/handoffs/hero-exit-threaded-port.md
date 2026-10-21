# hero-exit-threaded-port handoff

State: branch `worktree-wf_c2c26e40-d7b-1`. Note: `research/notes/2026/10-2x-hero-exit-threaded.md` (source decision per
property, CONFIRMED at WebKit@862f17d with path:line).

Built:
- `hero.exit:threaded` (`apps/site/src/parts/hero.exit/threaded.ts`, `threaded.module.css`, `index.tsx`, `part.json`).
  A view timeline on the track (`contain`, linear, `fill: both`); per consumer an opacity/transform/blur animation;
  only accelerated properties (opacity, transform, translate, filter) so no animation sets WebKit's throttle bypass.
- Hand-over: the original callback runs until `data-splash` is `done` in a browser with `animation-timeline` and without
  reduced motion (Lean `live`); then the callback stops, inline `--exit-opacity` is cleared, `data-exit-live` goes on
  the track, and a 1 px IntersectionObserver sentinel at 19/20 of the range owns `pointer-events`.
- Lean: section Threaded of `lean/Fw/Parts/HeroExitOpt.lean` (`live_*` one theorem per branch, `keyframe_table_*`,
  golden rows); generator `lean/scripts/ExitThreadedGolden.lean`, golden `packages/contracts/golden/parts/hero-exit.threaded.jsonl`.

Verified: site `pnpm test` (the TS twin is checked against the golden: endpoints, `anim` = `orig` at 690 sampled
offsets, sentinel, hand-over table, the CSS file's keyframes and conditions), `lean/scripts/check.sh`, build.

Writes outside the task's graph writes: `lean/scripts/check.sh` (+1 job), `lean/scripts/ExitThreadedGolden.lean`,
`lean/Fw/Ci/Trigger.lean` + `packages/contracts/golden/ci/triggers.jsonl` (new lean.yml input), regenerated
`FootprintData.lean`, `FootprintRows.lean`, `footprint.gen.json`, `footprint-diff.gen.json`,
`golden/preset/v2-proved.decisions.jsonl` (new registered variant).

Open: the phone replay (felt effect) and preset membership are follow-ups. `hero.countdown:hidden-pause` reads the
stage's inline `--exit-opacity`, which the hand-over clears (do not combine). Safari before 26.4 runs the animations on
the main thread. RG11 (`contain` range numbers under dynamic toolbars) is judged by the probe, not proved.
WebKit lane measurement with the corrected exit check (scrollY still runs plus a getComputedStyle consumer sample): no
lane supports it yet (named in the report as dispatch for the lead).

Read first: the note, then section Threaded in `HeroExitOpt.lean`, then `threaded.ts`.
