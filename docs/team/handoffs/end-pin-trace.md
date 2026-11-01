# Handoff: end-pin-trace (measure-engineer)

Branch `worktree-wf_96aeddfb-137-1`, worktree `.claude/worktrees/wf_96aeddfb-137-1`, CI branch `ci/end-pin-trace` (tip ffe701b77, the dispatch 2 push). The last commit is the branch tip (`git log -1`).

## CI runs (2 of 2 dispatches used)
- 41285184069 (smoothness, dispatch 1, 38ed79650): complete. Job 1 failed, 0 windows (simctl openurl timeout, no ready file after 285 s; harness). Job 2 success, 5 windows: pin windows 3 (refused noOpen, 24 calls, 19 inactive) and 5 (open, no stored lock, 10 calls, 0 writes).
- 41289882234 (smoothness, dispatch 2, ffe701b77, adds the due-check decline trace): success. Job 1 all 24 windows (6 pin windows, 1 write); job 2 8 windows (2 pin windows, 0 writes).
Results: `results/end-pin-trace/run-*/job{1,2}/touch-lock.{json,md}`. Per-window counts: the note.

## Verified (local)
Lean `sh lean/scripts/check.sh` green; site vitest 8552 pass, tsc clean; measure-webkit 1107 pass; ci-paths 56; runner land-inputs 73; plan lint 0 errors, no writesClosure warning for this row.

## Built
- `lean/Fw/Parts/EndPin.lean`: `writesLive_zero`, `faith_writesLive_witness`, target per event (`Ev.idle ms s`), `Why`/`Outcome`/`dueWhy` with iff theorems, `traceCounts`.
- `lean/Fw/Measure/TouchLock.lean`: `lockedCmp` (n/a when an arm stored no lock).
- TS: `end-pin.logic.ts`, `end-pin.live.ts`, `driver.ts` (trace hook `env.trace`), `index.tsx` (`window.__fwPinTrace`), checked against `packages/contracts/golden/measure/touch-lock.jsonl`. No TS stand-in.
- Lane: `packages/measure-webkit/src/touchlock{,-page,-run}.mjs` (pin entries per window, trace table, `lockedCmp` verdicts).

## Open
The user's look review (class L). More locked pin runs to rank the pin against base by fights (it wrote in 1 of 10 windows). The phone cadence of scroll events during a deceleration (INFERRED only).

## Read first
`research/notes/2026/11-01-end-pin-trace.md`, then `research/notes/2026/11-01-end-pin-no-fight.md`.

## Conventions
A ci push needs a lane token in the tip message. Use `pnpm -s fw ci wait --branch ci/end-pin-trace`. Regenerate golden with `lake env lean --run scripts/TouchLockGolden.lean > <file>` in `lean/`; `part.json` edits need `node apps/site/scripts/part-footprint.mjs --write`.
