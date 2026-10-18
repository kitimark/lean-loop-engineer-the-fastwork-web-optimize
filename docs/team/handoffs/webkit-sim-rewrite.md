# webkit-sim-rewrite handoff

State: branch worktree-wf_3766c904-1ef-1, code commit 8c72a66 (+ main merges, head cceee70 before this note). CI branch ci/webkit-sim-rewrite.

What it does: webkit-sim.yml serves the rewrite (apps/site, prerendered) with `?fw=`/`?preset=` flags beside the original arm.
- Lean (lean/Fw/Measure/SimPlan.lean, op measure.simPlan): arms (original|rewrite|both), refusals (11 checks), search query, job matrix
  (v<i> original then r<i> rewrite per index), pairing (partner of r<i> is v<i>), when a result counts. Goldens:
  packages/contracts/golden/measure/measure.simPlan.jsonl (14 cases).
- Glue: packages/measure-webkit/src/simplan.mjs (env -> fwcore -> step outputs), test/simplan.test.mjs (3 tests).
- cli.mjs: determinism save records `site: {search, configHash}` for the rewrite arm.
- Workflow: fwcore job first, plan job (Lean decides), site job builds `--config "$SEARCH"`, sim matrix has `search`, align summary prints "pages served".

CI (run 39104964068, dispatch target=both vms=1 sessions=1 fw=hero.countdown:strip): all 9 jobs green; the push run was cancelled by the dispatch.
Rewrite page served: `?fw=hero.countdown:strip`, configHash 7d81120ee5a22b80 (default 6bb2a28a0d5befeb), vw 430, hydrated true, no errors.
Paired counts, full zones (10 zones), pass1/pass2, original -> rewrite: RecalculateStyles 683/666 -> 436/438, Layout 615/616 -> 181/180,
Paint 1216/1254 -> 462/449, Composite 199/199 -> 199/199. One VM, so it is a smoke result: classes need >= 3 runs (Fw/Measure/Classes).
Original page docH 6042 vs rewrite 6620 (different layouts, not a defect of the lane).

Dry land needs `--allow 'lean/Fw/Measure/*.lean' --allow lean/Fw/Ops/LakeJobsGen.lean` (task writes list only names the workflow and src).
node_modules in a fresh worktree: `pnpm install --offline --frozen-lockfile` before `pnpm fw ...`.

Open: 3-run classing of the F5 fixtures on the rewrite; extend --fw to P2-P5 presets via dispatch inputs (`fw`, `preset`); work-graph `writes` should list lean/Fw/Measure/SimPlan.lean.
Read first: lean/Fw/Measure/SimPlan.lean, .github/workflows/webkit-sim.yml (plan job).
