branch: worktree-wf_bcca31ed-d99-1 (CI branch ci/wk-loop-freeze, pushed)
worktree: .claude/worktrees/wf_bcca31ed-d99-1 (under the repo root)
last commit: b3f0299cb (merge of main: already up to date)
CI runs (2 of 2 dispatches, both vms=3 target=rewrite, in progress): base 40390428285 (nonce wklfbase0001); flag 40390434234 (nonce wklfflag0001, fw=platform.glint:hold-freeze). Push run 40390226262 (lean only, completed).
Wait: pnpm -s fw ci wait --branch ci/wk-loop-freeze --nonce wklfbase0001 (and wklfflag0001), in the background.

Verified (local, through fw slot): lean/scripts/check.sh green; @fw/measure-webkit test 938/938; scripts/ci-paths.test.mjs 56/56; apps/runner test/land-inputs.test.ts 73/73.
Open: CI re-measure (lost/total against wk-sim-hang 0 of 7), plan lint, dry land, review ready.

State: the two losses are runner-VM freezes (memory exhaustion, swap thrash), MEASURED; the reboot's `terminate Safari` overran on a fresh boot.
Fix: Lean `Freeze` section in lean/Fw/Measure/SimHost.lean (silence clock skips a freeze, `failsIn` drops stale probe streaks, `relaunchPlan fresh` omits terminate), golden ops silence/streak/plan in sim-host.jsonl, TS in watchdog.mjs, guard.mjs, session.mjs, sim-host.mjs.
Read first: research/notes/2026/10-2x-wk-loop-freeze.md.
Conventions: golden is regenerated from Lean (`lake env lean` on SimHostGolden.lean), never hand-edited.
Follow-ups: per-process RSS at low free memory; Simulator daemon load; silent stall of attempt 2 (run 40349930733 r2); cpu ratio as freeze signal.
