# Handoff: webkit-lag-probe (measure-engineer)

Branch `worktree-wf_4ab15aff-5d3-1`, CI branch `ci/webkit-lag-probe`. Read first:
`research/notes/2026/10-21-webkit-lag-probe.md` (ranked attribution, counter citations, limits).

## State
- Lane: `packages/measure-webkit/src/lag/` (`probe.mjs` in-page sampling and sessions, `report.mjs` join and Markdown,
  `reduce.mjs` TS twin, `cli.mjs` `run` and `report`). Dispatch: `gh workflow run webkit-sim.yml --ref
  ci/webkit-lag-probe -f lag=true -f target=both -f vms=3`. The `lag-report` job needs all sim jobs green.
- Lean: `lean/Fw/Measure/WebKitLag.lean` (owner, regions, ledger, filters, ranking), golden
  `packages/contracts/golden/measure/webkit-lag.jsonl` built by `lean/scripts/WebkitLagGolden.lean`.
- MEASURED: run 39511908073 (v1..v3, r1..r3, 2 scroll and 2 morph passes each), cross-check 39503100190.

## Verified
- `pnpm --filter @fw/measure-webkit test`, ci-paths test, runner land-inputs test, `sh lean/scripts/check.sh`.
- Not verified: the `lag-report` CI job itself (skipped in both runs because a sim job failed); the report was run
  offline on the downloaded `webkit-sim-*` artifacts with the same CLI.

## Open
- Rect attribution is INFERRED (Paint `nodeId` absent without a DOM agent): follow-up reads the node id.
- Page height differs by 36 px between loads; timed steps join geometry by nearest y.
- Sim jobs stall sometimes (Runtime.evaluate timeout, no page target); the probe keeps completed passes.
- Pre-existing, not ours: actionlint error at `webkit-sim.yml:57`; `Keep logs and host state` step timeouts.

## Conventions
- Writes outside the graph: `.github/workflows/webkit-sim.yml`, `lean/Fw.lean`, `lean/scripts/check.sh`,
  `lean/scripts/WebkitLagGolden.lean`, `lean/Fw/Store/Layout.lean` (`lag` lane input), `lean/Fw/Ci/Trigger.lean`,
  `packages/contracts/golden/ci/triggers.jsonl` (generated).
- TS stand-ins: in-page JS, clip conversion, nearest-y join, report means, ratios, classes and Markdown, retries.
- Candidate fixes are judged against rank 1 and 2 rows of the note's table, on 3 jobs per arm.
