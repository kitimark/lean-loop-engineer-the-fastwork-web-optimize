# node-pin-local handoff (round 2)

State: branch worktree-wf_d0d6e462-6cd-1, main (3cc1a065) merged. Read first: lean/Fw/Ci/Trigger.lean section "The Node pin rule".
- .nvmrc 24.22.0 (CONFIRMED: installed nvm 0.39.7 has no .node-version lookup); package.json engines.node; .npmrc engine-strict; pnpm useNodeVersion; all equal .node-version (copyProblems).
- Step order (r1 high): PinJob.nodeBeforeSetup + jobProblems "nodeBeforeSetup" + theorem jobProblems_nodeBeforeSetup, golden pinJob lines (3 new), TS twin in
  jobFacts (first run:/node-action line before first setup-node/setup-pnpm line). 14 jobs fixed by moving the setup step directly after checkout
  (breakpoint-gate gate, chromium-counts counts, gate-gaps x2, snapshot-extract, trajectory-probe x2, visual-diff x5, webkit-sim, wktr).
  Exempt in Lean (PinJob docstring): the telemetry action, a best-effort sampler that skips itself without node; 19 in r1 counted it. Limit: telemetry start may run on the runner's Node.
- Refuse-or-run (r1 medium): Lean nodePinRefusal + theorems (_none_noPin, _none_iff, _some_iff), golden pinGuard lines (10); TS twins in scripts/ci-paths.mjs and both apps/*/src/node-guard.ts; apps/*/test/node-guard.test.ts assert equality with the golden.
- pinValueProblems theorems: _noFile, _notExact, _tooOld, _ok. ci-paths: unreadable jobs are now a problem, not silence.
- Verified (local, debug): lean/scripts/check.sh green; ci-paths.test.mjs 49/49; ci-paths --check green; runner 1514/1514; console-api 575/575.
- CI: ci/node-pin-local, run 39456448428 (lean workflow, success): guard and lean jobs log `node: v24.22.0` (setup-node step 4 s, right after checkout). MEASURED.
  All other lanes were skipped by their guards, and the lean job runs no pnpm, so pnpm's useNodeVersion download cost is NOT measured. Open: dispatch a pnpm lane
  (e.g. premise-tests) on ci/node-pin-local and read the setup-pnpm "pnpm install" step time; if large, export npm_config_use_node_version empty in the setup-pnpm action.
- TS stand-ins: YAML reader jobFacts, .npmrc engine-strict check. Follow-ups: .claude/settings.json hooks run `node` from PATH unguarded; jobFacts misses node started from shell scripts (check-simulator.sh).
- Writes outside the graph list: none new (work-graph.json taken from main, lead-only).
