branch: worktree-wf_bcca31ed-d99-1 (CI branch ci/wk-loop-freeze at b3f0299cb, pushed)
worktree: .claude/worktrees/wf_bcca31ed-d99-1
last commit: code at b3f0299cb; later commits are note and handoff only
CI runs (2 of 2 dispatches used, vms=3 target=rewrite): base 40390428285 complete failure (r3 success, r2 exit 4, r1 cancelled after 58 min); flag 40390434234 (fw=platform.glint:hold-freeze) complete success 3 of 3. Lost 2 of 6 against wk-sim-hang 0 of 7.

Verified: lean/scripts/check.sh green; @fw/measure-webkit test 938/938; scripts/ci-paths.test.mjs 56/56; apps/runner land-inputs 73/73; plan lint 0 errors; dry land VERDICT dry wk-loop-freeze.
Open: the two base losses are other classes (Simulator wedged with steady sampler; VM gone for 34 min). Lead decides whether a follow-up task takes them.

State: the original two losses are runner-VM freezes (swap thrash), MEASURED; the reboot's `terminate Safari` overran on a fresh boot.
Fix: Lean `Freeze` section in lean/Fw/Measure/SimHost.lean (silence clock skips a freeze, `failsIn` drops stale probe streaks, `relaunchPlan fresh` omits terminate), golden ops silence/streak/plan in sim-host.jsonl, TS in watchdog.mjs, guard.mjs, session.mjs, sim-host.mjs.
Read first: research/notes/2026/10-2x-wk-loop-freeze.md; data in results/wk-loop-freeze/data/.
Conventions: golden is regenerated from Lean (`lake env lean` on SimHostGolden.lean), never hand-edited.
Follow-ups: Simulator wedge (simctl and inspector time out, no VM freeze); per-process RSS at low free memory; silent stall of attempt 2 (run 40349930733 r2); cpu ratio as freeze signal; non-fresh relaunch can still overrun terminate on a wedged device.
