# Handoff: end-pin-trace (measure-engineer)

Branch `worktree-wf_96aeddfb-137-1`, worktree `.claude/worktrees/wf_96aeddfb-137-1`, CI branch `ci/end-pin-trace`. Last commit at dispatch 1: 38ed79650; dispatch 2 is the tip commit of ci/end-pin-trace.

## CI runs
- 41285184069 (smoothness, dispatch 1, 38ed79650): complete. Job 1 failed with 0 windows (simulator never gave a tab: simctl openurl timeout, no ready file after 285 s; harness, not this code). Job 2 success, 5 windows (walk deadline 1654 s): pin windows 3 (refused noOpen, 24 pin calls, 19 inactive) and 5 (open, 119 frames, no stored lock, 10 calls: 2 inactive, 4 touch, 2 moved, 1 touching, 0 due, 0 writes). Results: results/end-pin-trace/run-41285184069/job{1,2}/.
- dispatch 2: pending (adds the due-check decline trace, dueWhy)

## Verified (local, not a result)
Lean `sh lean/scripts/check.sh` green; site vitest 8551 pass and tsc clean; measure-webkit tests 1107 pass; ci-paths 56 pass; runner land-inputs 73 pass; plan lint 0 errors, no writesClosure warning for this row.

## Built
- `lean/Fw/Parts/EndPin.lean`: `writesLive` (writes made while `live`), `writesLive_zero`, `faith_writesLive_witness` (= 2), target per event (`Ev.idle ms s`), `Why`/`Outcome` with iff theorems, `traceCounts`.
- `lean/Fw/Measure/TouchLock.lean`: `lockedCmp` (n/a when an arm stored no lock); golden op `lockedCmp`.
- TS: `end-pin.logic.ts` (`why`, `outcome`), `end-pin.live.ts` (twins of `writesLive`, `faithWritesLive`), `driver.ts` (trace hook), `index.tsx` (`window.__fwPinTrace`), all checked against `touch-lock.jsonl`.
- Lane: `touchlock-page.mjs` (hook, per-window entries), `touchlock.mjs` (`traceCounts`, `lockedCmp`, trace table), `touchlock-run.mjs`.

## Open
CI trace counts per pin window; the note `research/notes/2026/11-01-end-pin-trace.md`; the ledger row; the user's look review (class L).

## Conventions
A ci push needs a lane token in the tip message. Use `pnpm -s fw ci wait --branch ci/end-pin-trace`. Max 2 dispatches.
