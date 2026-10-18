# Handoff: webkit-sim-rewrite (webkit-sim.yml serves ?fw= on the rewrite arm)

State: branch worktree-wf_a1287381-4b7-1, pushed to ci/webkit-sim-rewrite. Base is the Lean-first version of the
earlier builder (Fw.Measure.SimPlan decides arms, flags, pairing; `plan` job runs fwcore). The TS-only `sitePlan` variant of
worktree-wf_d00caaf1-127-2 was dropped: the pushed branch already had a superset, and a force push is forbidden.
Merged main; the workflow got main's guard/tip re-check/concurrency by `node scripts/ci-paths.mjs --write`.

Verified: lean/scripts/check.sh green, measure-webkit 88 tests pass, ci-paths --check ok, `fw land --dry` = VERDICT dry
(needed --allow lean/Fw/Measure/Golden.lean, lean/Fw/Measure/SimPlan.lean, lean/Fw/Ops/LakeJobsGen.lean: the Lean plan).

Runs (target=both, fw=hero.countdown:strip, 430 px, 1 VM, 1 session; the session JSON carries site.search + configHash):
- 39104964068 (head 96dcee05, earlier builder): green, settled, 23m
- 39123585294, 39123621097 (head 40a8d4c1, dispatched 18:31 +07, separate jobs): see the report; results in the run artifacts.

Open
- Class counts need >= 3 runs on separate jobs and the agreement across them; one run is not a result. P1-P5 flags other
  than hero.countdown:strip are not run. A push never runs the lane unless the head commit has `[ci:webkit-sim]`.
- If a lane stalls (simctl ETIMEDOUT, seek stall), it is not a count; never rerun --failed.
- C3 (2026-10-19 23:15 +0700): not green by then -> WebKit stays model-only.

Read first: Fw/Measure/SimPlan.lean, .github/workflows/webkit-sim.yml `plan`, docs/team/handoffs/step-align.md.
