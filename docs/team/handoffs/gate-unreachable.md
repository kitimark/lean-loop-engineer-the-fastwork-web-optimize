# Handoff: gate-unreachable (Q33, Lean first)

## State
- Branch `worktree-agent-a7e18fbcda8c83f85`, one commit "lean: gate unreachable cells ..." on top of 342a9fb.
- `sh lean/scripts/check.sh` green; `pnpm --filter ./packages/gate-breakpoints test` 18/18; standard axioms only.

## What exists
- `Fw.Gate.Rule`: `Reason` (primaryPair, wholeWidth, widthDpr), `Verdict.unreachable r`; `rollup` is unreachable
  only when every verdict is; `Tally.total` counts pass+fail only, `Tally.unreachable` the rest (`tally_counts`).
  Order independence: `rollup_perm`, `rollup_flatten`, `rollup_filter_unreachable`, `tally_filter_unreachable`.
- `Fw.Gate.Reach` (new): `Port` (chromium, webkitApple, webkitGLib), primary pairs, `Port.reason` (first match:
  pair, whole width, whole device px), matrix theorems `matrix_webkit_unreachable_iff` (exactly the 4 fractional +
  4 cross probes on both WebKit ports) and `matrix_chromium_reachable`.
- `Fw.Gate.State`: `Ctx.port`, `reqReason`, `stateReach`, `reachRows`; `StateOut.reach`, `StateOut.verdict`
  (rollup over all rows, part rows included: `evalState_part_fail`), `StateOut.itemFails`.
- `Fw.Site.BreakpointMatrix`: fractional probes at DPR 2 (`matrix_width_dpr_whole`, `matrix_whole_iff`,
  `fractional_dpr_indep`); both `breakpoints.gen.json` differ only in 4 `dpr` values.
- Wire: `gate.state` takes optional `port`, replies `reach` and `verdict`; `gate.tally` replies `unreachable`;
  new op `gate.reach {port, envs}` -> `reasons`. Verdict names `unreachable:<primary-pair|whole-width|width-dpr>`.
- Goldens: `literal.jsonl` gained 9 cases (incl. reach over the whole matrix per port); regenerate with
  `cd lean && lake env lean --run scripts/GateGolden.lean`.

## Conventions
- Unreachable comes only from `Port` facts proved here, never from a runtime observation.
- An unreachable state lists no failing item (`itemFails`), so `fails` is empty on the wire.

## Open items (for gap-harness)
- `packages/gate-breakpoints/src/summary.mjs` does not pass `port` to `context(...)` yet and ignores
  `verdict`/`unreachable`; it must pass the engine's port and print unreachable cells.
- Harness must load fractional probes at DPR 2 (gen.json already says so).

## Read first
`lean/Fw/Gate/Reach.lean` (module doc), then `lean/Fw/Wire/Gate.lean` op table.
