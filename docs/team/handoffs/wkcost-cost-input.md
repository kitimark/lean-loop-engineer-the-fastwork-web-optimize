# Handoff: wkcost-cost-input

State: branch `worktree-wf_64810607-67c-1`, pushed as `ci/wkcost-cost-input` (the dispatch ran on its tip 0ee55e97).

## Delivered
- `webkit-sim.yml`: `cost` workflow_dispatch input (choice `'off'|'on'|only`, default `'off'`), env `COST`, passed as `--cost "$COST"` to `lag/cli.mjs run`. No commit token; a push has no inputs so it is `off`.
- `packages/measure-webkit/src/lag/costmode.mjs` (`parseCost`) used by `lag/cli.mjs run`; anything but off|on|only throws before a session opens.
- `test/lag-cli-cost.test.mjs` (4 tests): mode map, bad values throw, the CLI exits 1 on `--cost bogus`, the workflow options are quoted and `--cost "$COST"` is in the lag step.

## Gotcha
YAML 1.1 reads bare `off` and `on` as booleans: GitHub refused `cost=on` (HTTP 422) until the options were quoted. The workflow test pins the quoting.

## The dispatch
- `gh workflow run webkit-sim.yml --ref ci/wkcost-cost-input -f lag=true -f target=both -f vms=3 -f cost=on -f nonce=wkcostin1`
- Run 39696054101: failure, because sim job v3 (original arm, VM 3) lost its Safari tab during the pass 1 cost passes (page target lost, relaunch ETIMEDOUT, exit 5). v1, v2, r1, r2, r3 succeeded.
- Cost tables appear: the `webkit-sim-*` artifacts hold the cost passes (original 4/4 passes, rewrite 6/6 with cost counters); `lag/cli.mjs cost-report` on them prints all five tables (cadence, histogram, paint vs composite, layers, paint after morph). The `webkit-lag-report` artifact holds no cost tables; run cost-report on the per-VM JSON.

## Open items (follow-ups, outside the unit)
- v3 original job lost its page target in the cost passes (same family as the rewrite-arm failures in webkit-cost-counters).
- 35 min sim step bound is tight for lag + cost; not touched.
- `v2-proved` is still empty (preset arm is an A/A control).

## Read first
`research/notes/2026/10-2x-webkit-cost-counters.md`, `docs/team/handoffs/webkit-cost-counters.md`.
