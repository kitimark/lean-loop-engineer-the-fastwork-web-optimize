# node-pin-local handoff

State: branch worktree-wf_d0d6e462-6cd-1. node-pin was not on main yet, so this branch merged its land candidate daa2cde6 (b9ae4fc9);
merge main once node-pin lands (same content, should be clean).
- .nvmrc = 24.22.0. CONFIRMED: the installed nvm 0.39.7 (~/.nvm/nvm.sh) has no `.node-version` lookup (grep finds none), so .nvmrc is needed;
  `copyProblems` in the ci-paths check makes it equal .node-version.
- pnpm 10.34.5: `useNodeVersion: 24.22.0` in pnpm-workspace.yaml (pnpm CHANGELOG v10.34.5: use-node-version and executionEnv.nodeVersion entries; exec/run honour it;
  pnpm.io/settings has no entry, the changelog is the source). LOCAL DEBUG RUN (not a result): PATH with 24.14.0 first, `pnpm run`/`pnpm exec` print v24.22.0.
  Cost: pnpm downloads that Node into its store once (also in CI, untested there).
- package.json engines.node = "24.22.0"; .npmrc engine-strict=true (workspace packages say >=24, which 24.22.0 meets).
- Runtime guard: apps/runner/src/node-guard.ts and apps/console-api/src/node-guard.ts (same text), called in fw.ts and main.ts; tests in both test/node-guard.test.ts.
  Debug run under 24.14.0: `node apps/runner/src/fw.ts` and console-api main print "refusing to start: running Node 24.14.0 but .node-version pins 24.22.0; run nvm install && nvm use ..." and exit 1.
  Imports hoist, so the guard runs after module load, not before.
- Lean: Fw.Ci.Trigger section "The Node pin rule": pinValueProblems, jobProblems, rowProblems, copyProblems, one theorem per OR-branch, golden `pin*` lines in
  triggers.jsonl (regenerated). lean.yml row now lists .node-version. TS twins in scripts/ci-paths.mjs checked by ci-paths.test.mjs.
- Workflows: setup-node step added to all 17 guard jobs, chromium-counts plan and image, lean.yml lean job. The check now flags a Node job without setup-node
  (composite actions that run node count for their callers), quoted and flow-map setup-node forms, and a workflow with no Lean row.
- Verified: ci-paths --check green, ci-paths.test.mjs 49/49, lean/scripts/check.sh green, console-api pnpm test 574 pass.
  runner pnpm test 1512/1513: the one failure is incidents.test.ts "ledger lints with 0 errors" (inc-lead-cd-cwd unknownKind/unknownHardening), from the
  ledger commit on main, not this branch.
- TS stand-ins: the YAML reader jobFacts and the `.npmrc` engine-strict line check (no Lean twin).
- Writes outside the graph writes: apps/*/src/node-guard.ts, apps/*/test/node-guard.test.ts, lean/Fw/Ops/CheckMap.lean (nvmrc/npmrc text kinds, else the commit checkmap refuses them).
- Open: no CI run yet (workflow files changed): push ci/node-pin-local and read that the guard and lean jobs log `node: v24.22.0` and pnpm's extra download time.
  The user's shell snapshot finding 24.14.0 first still works through pnpm, and direct `node apps/...` refuses by the guard.
