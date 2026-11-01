# Handoff: end-pin-no-fight (measure-engineer)

Branch `worktree-wf_495bf26b-5b0-1` (merged with main), CI branch `ci/end-pin-no-fight` at d63c5f9e9. Worktree `.claude/worktrees/wf_495bf26b-5b0-1`. Read first: `research/notes/2026/11-01-end-pin-no-fight.md`, then `lean/Fw/Parts/EndPin.lean`.

## State
Done: Lean model and proofs, TS twin and driver wiring (flag `morph.tween:end-pin`, class L), lane `pin` arm, 3 CI dispatches (the maximum), note, ledger row. Open: the user's look review (ledger `userDecision` pending).

## Built
- `lean/Fw/Parts/EndPin.lean`: write only when no touch, 120 ms quiet, off target, not reversing. `pin_fights_zero` (user positions must avoid the target), `faith_fights_witness`, `decline_rests_off_target`.
- `lean/Fw/Measure/TouchLock.lean`: `openCalls`, `Arm.pin`, 4-arm `repOrder`. Golden rows `pin*` in `packages/contracts/golden/measure/touch-lock.jsonl`.
- `apps/site/src/parts/morph.tween/{end-pin.logic.ts,driver.ts,index.tsx,part.json}`, `end-pin.golden.test.ts`.
- Lane: `packages/measure-webkit/src/touchlock*.mjs` (pin arm, `armPath` keeps `?fw=`), `smoothness.yml` touch-lock matrix `[1,2]`.

## CI runs (smoothness, push of ci/end-pin-no-fight, tags in the tip message incl. `[ci:smoothness]`)
- 41267567864 (0ce0723a6): success; job 1 and 2 results; pin windows all refused `config` (URL reset dropped `?fw=`).
- 41270567124 (5faf65ca7): job 1 over 45 min, no artifact; job 2 result, pin 3 accepted.
- 41275699141 (d63c5f9e9): job 1 stalled (`swipeLate`) and its upload timed out, no artifact; job 2 result, pin 1 accepted.
Results: `results/end-pin-no-fight/run-*/job*/`, pooled `results/end-pin-no-fight/pooled/touch-lock.md`.

## Verified
`sh lean/scripts/check.sh` green (6be0a32e2), site vitest 8547 pass, tsc clean, measure-webkit tests pass, ci-paths 56 pass.

## Extra writes outside the task list
`lean/Fw/Parts/FootprintData.lean`, `packages/contracts/golden/parts/footprint.gen.json`, `apps/site/scripts/part-footprint.mjs` (the generated list needs `set_option maxRecDepth`), `packages/contracts/golden/preset/{look-change.candidates,shipped.decisions}.jsonl` (generator).

## Conventions
Commit hook runs checkmap (slow when Lean files are staged). A ci push needs a lane token such as `[ci:smoothness]` in the tip message. Use `fw ci wait` (540 s per call).
