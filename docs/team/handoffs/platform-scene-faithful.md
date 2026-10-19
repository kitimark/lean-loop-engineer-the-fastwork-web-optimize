# platform-scene-faithful handoff

State: branch worktree-wf_ebd5ee90-ef5-2, one commit. The platform faithful arm now carries the original's scene attribute and paused rule.

Delivered
- `lean/Fw/Parts/PlatformScene.lean`: `near`/`attr`/`sceneOf` (original `lE`, `dE`), CSS local-time model (`advance`, `local'`), theorems `faithful_eq_original`, `local_paused_span`, `local_append_paused` (resume keeps the frozen phase, no seek), `local_mono`, `sample_paused_span`, `loop_periodic`, `oneShot_before`, `oneShot_after`; the animation lists `oneShots` (18 entries, fill both, per-index delays) and `loops` (90 s, 4 s, 1 s).
- Golden `packages/contracts/golden/parts/platform.scene.jsonl` (from `PlatformGolden.sceneLines`, regenerated with `fwcore partsgolden`).
- `apps/site/src/parts/platform/scene.ts` (`sceneOf`, `bindScene`), `index.tsx` calls `bindScene(sec, watchActive)`, `platform.module.css` paused rule (restated from snapshot CSS 11754-11758, scoped to `.section`).
- Tests `platform/scene.test.ts`: golden conformance, attribute toggled by a fake observer and removed on teardown, CSS rule text.
- `footprint.gen.json` and `FootprintData.lean` regenerated with `node apps/site/scripts/part-footprint.mjs --write` (the CSS rule changes the platform footprint).

Verified: `lake build Fw`, site typecheck + test (svg-extract test times out at 5 s under load, passes alone with a longer timeout), runner test, ci-paths test.

Open
- Only `watchActive`'s activity and the paused CSS are ported; `deferRendering` (content-visibility) is not in this unit (follow-up).
- Pixel equality of paused vs original: gate/visual run.
- TS stand-in: none beyond `bindScene` glue.
