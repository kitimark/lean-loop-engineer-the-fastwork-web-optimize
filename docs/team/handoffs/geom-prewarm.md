branch: worktree-wf_066a7844-684-1 (CI branch ci/geom-prewarm)
worktree: .claude/worktrees/wf_066a7844-684-1 (under the main checkout)
last commit: see `git log -1` (before push 1: 5ee65ddef plus this file)
CI runs: none yet (push 1 pending)

State
- Lean `lean/Fw/Parts/MorphGeomPrewarm.lean`: refStep (landed driver) vs newStep (prewarm), `same_look` (look equal after any event list from a clean page, by the simulation `run_sim`), `held_push_no_create`, `warm_then_push`, `held_stale_falls_back`, `held_refused_leaves`, `settle_zero_base`, `dispose_base`, `no_warm_same`. Golden `packages/contracts/golden/parts/morph-geom-prewarm.jsonl` (10 scenarios), check.sh job, Trigger row, triggers.jsonl regenerated.
- TS `apps/site/src/parts/morph.tween/geom-timed.driver.ts`: `warm()` enters the flip tree and creates the 0 to 1 tracks paused; `take(0,1)` on a held set only sets startTime; stale viewport, refused push, settle, dispose leave. `driver.ts` calls warm when near and idle at 0 (setNear, pin, end of a flip), cool when not near; `index.tsx` cools on resize. Test `geom-timed.prewarm.golden.test.ts` replays the golden.
- Probe `packages/measure-wktr/src/mid-page.mjs` adopts held tracks into the arm (fields prewarmed, createdOnPush). Workflow wktr.yml: commit message token `[accel-prewarm]` runs modes mid,mid-thr-off with arms all,all-again.
- Verified locally: check.sh green, site vitest 8467 passed, typecheck, measure-wktr tests.
Open: CI numbers (WKTR pref off first flip ticking tracks mid-tween; gate flip cell and verify; look report), note research/notes/2026/10-2x-geom-prewarm.md, ledger, dry land, review ready.
Conventions: TS stand-ins: tween driver warm/cool call sites (no Lean golden of when the driver calls them); resize cool.
