# hero-exit-threaded-measure handoff

Branch `worktree-wf_34794772-0e5-1` (CI copy `ci/hero-exit-threaded-measure`), worktree
`.claude/worktrees/wf_34794772-0e5-1`. Last commit: `git log -1` (base bb6a5df2 + this update).

CI runs (webkit-sim, `gh workflow run webkit-sim.yml --ref ci/hero-exit-threaded-measure -f lag=true -f target=rewrite -f vms=3 -f cost=on [-f fw=hero.exit:threaded] -f nonce=<n>`):
- base arm, nonce hetmbase1: run 39731185714. r3 success; r2 FAILED (exit 4: Simulator Shutdown after a failed inspector, not a lost page target; log in artifact webkit-sim-r2); r1 still in "Determinism sessions" at checkpoint 2.
- flag arm `fw=hero.exit:threaded`, nonce hetmflag1: run 39731192687, complete, success, r1 r2 r3 all with 2/2 passes and cost ok.
Dispatches used: 2 of 4. Artifacts downloaded to scratchpad dirs flag/ (done) and base/ (r3 only so far).

Verified: nothing reduced yet. Open: base r1 result; if base ends with < 3 VMs consider `gh run rerun --failed` (not a new dispatch) or dispatch 3 (base again); reduce with
`node packages/measure-webkit/src/lag/cli.mjs cost-report --original <base jsons> --rewrite <flag jsons>` and `report`
(Recalculate styles / Layout per step in the report), write ledger row update, results/hero-exit-threaded-measure/report.json, note.
