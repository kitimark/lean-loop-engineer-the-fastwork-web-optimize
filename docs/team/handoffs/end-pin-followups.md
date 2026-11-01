# Handoff: end-pin-followups (lean-prover)

Branch `worktree-wf_79765b7c-dcf-1`, worktree `.claude/worktrees/wf_79765b7c-dcf-1`. The last commit is the branch tip (`git log -1`). No CI push, no CI run (accepted limit).

## Verified (local)
`sh lean/scripts/check.sh` green; site 8553 pass + typecheck clean; measure-webkit 1108 pass; ci-paths 56; runner land-inputs 73; plan lint 0 errors (only `longTitle` for this row); `VERDICT dry end-pin-followups`; `VERDICT review-ready end-pin-followups review`.

## Built
- `lean/Fw/Parts/EndPin.lean`: `Policy`, `faithMay`, `stepBy` (`step := stepBy mayWrite`), `playBy` (`playBy_mayWrite`), one `writesLive may`, `writesLive_zero_of`, `writesLive_zero`, `faithEvents`, `faith_play`, `faith_writesLive`, `faith_writesLive_is_writes`, `faith_writesLive_pos`, `liveEvents` with `faith_writesLive_witness` (2) and `end_writesLive_witness` (0). `faithWritesLive`, `pass`, `faithWritesLive_eq` deleted.
- Golden `packages/contracts/golden/measure/touch-lock.jsonl` (12 play rows; `faithWritesLive` is `writesLive faithMay`).
- Site: `end-pin.live.ts` (`writesLive(may, ...)`, `faithMay`), `end-pin.logic.ts` (`Policy`, `idle`/`play` take a policy), `end-pin.trace.ts` (`withPinTrace`: `env.trace` getter over `window.__fwPinTrace`), `index.tsx`, `end-pin.trace.test.ts`, `part.json` provenance; footprint regenerated.
- `packages/measure-webkit/src/touchlock.mjs`: `rankedOf`, `RANKED_TEXT`, `rankedText`, `verdicts.ranked`, the selection line in `markdown`.

## Open
The user's look review (class L). Momentum coverage INFERRED. More locked pin runs to rank the pin against base.

## Read first
`research/notes/2026/11-01-end-pin-followups.md`, then `research/notes/2026/11-01-end-pin-trace.md`.

## Conventions
Regenerate the golden in `lean/`: `lake env lean --run scripts/TouchLockGolden.lean > ../packages/contracts/golden/measure/touch-lock.jsonl`. After any site edit or main merge: `node apps/site/scripts/part-footprint.mjs --write`.
