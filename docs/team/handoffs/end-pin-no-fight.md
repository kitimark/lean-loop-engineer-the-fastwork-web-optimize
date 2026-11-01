# Handoff: end-pin-no-fight (measure-engineer)

Branch `worktree-wf_495bf26b-5b0-1`, CI branch `ci/end-pin-no-fight`. Worktree `.claude/worktrees/wf_495bf26b-5b0-1`.
Last pushed commit: 0ce0723a6 (empty, tags `[ci:smoothness] [webkit-cadence] [sim-only] [touch-lock]`); code in 6be0a32e2. State: model, TS twin, driver wiring and lane arm done; CI dispatch 1 of 3 pushed, waiting.

## Built (uncommitted before the first commit, then committed)
- `lean/Fw/Parts/EndPin.lean`: page-end pin policy (write only when no touch, 120 ms quiet, off target, not reversing). Theorem `pin_fights_zero` (needs user positions != target), `faith_fights_witness`, `decline_rests_off_target`. Look class L.
- `lean/Fw/Measure/TouchLock.lean`: `openCalls`, `Arm.pin`, `repOrder` with 4 arms. Golden rows `pin*` live in `packages/contracts/golden/measure/touch-lock.jsonl` (no new check.sh job).
- `apps/site/src/parts/morph.tween/{end-pin.logic.ts,driver.ts,index.tsx,part.json}`: flag `morph.tween:end-pin`; `end-pin.golden.test.ts` checks the rows and the driver glue.
- Lane: `packages/measure-webkit/src/touchlock*.mjs` has a `pin` arm (`?fw=morph.tween:end-pin`), `openCalls`/unrestored counts, pin verdicts; `smoothness.yml` touch-lock matrix is `[1,2]`.
- Ledger row `morph.tween:end-pin` (status look-change, webkit "pending").

## Verified locally (not a result)
site vitest 8547 pass, tsc clean, measure-webkit node tests 1101 pass, ci-paths 56 pass, part-footprint regenerated.

## CI runs
- dispatch 1: push of ci/end-pin-no-fight at 0ce0723a6, smoothness workflow, run 41267567864, in progress (lean run success; the other workflows skipped by design). `sh lean/scripts/check.sh` green on 6be0a32e2.
- dispatch 1 result: success, but all 6 pin windows per job-1 refused `config` (the window reset the URL to `/`, dropping `?fw=`); job 2 had a pageLost early (1 base window). Fixed by `armPath` in touchlock-run.mjs (5faf65ca7). Job results in `results/end-pin-no-fight/run-41267567864/job{1,2}`.
- dispatch 2: run 41270567124 at 5faf65ca7. Job 1 hit the 45 min job limit (walk step failed, no artifact, no log). Job 2 success: orig 3, base 3, lock 3, pin 3 accepted (+1 pageLost); pin made 0 scrollTo calls in every window (fights and displaced 0 by definition), in all 3 the page rested exactly at maxY10 (the base rests 0.6 px or more above it, in the overscroll). Results `results/end-pin-no-fight/run-41270567124/job2`.
- dispatch 3 (last): pushed after dispatch 2, see the next line when known.
- The commit hook needed `set_option maxRecDepth` in generated FootprintData.lean (`apps/site/scripts/part-footprint.mjs`, an extra write); the tip message needs a lane token `[ci:smoothness]`.

## Open
- Push `ci/end-pin-no-fight` with `[webkit-cadence] [touch-lock] [sim-only]` and `[trajectory fw=morph.tween:end-pin]`; at most 3 dispatches, 2 jobs each.
- Write `research/notes/2026/11-01-end-pin-no-fight.md`, update ledger row (webkit, run ids) then rerun `Fw.Preset.Gen.run ["--write"]`.
- Extra writes outside the task list: `lean/Fw/Parts/FootprintData.lean`, `packages/contracts/golden/parts/footprint.gen.json` (part-footprint --write), `packages/contracts/golden/preset/{look-change.candidates,shipped.decisions}.jsonl` (preset generator).
- Read first: `lean/Fw/Parts/EndPin.lean` header, then the note.
