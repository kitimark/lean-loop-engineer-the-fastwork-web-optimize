branch: worktree-wf_6ebfd006-dac-1 (CI branch ci/faithful-control-oos, pushed at 82c7820)
worktree: .claude/worktrees/wf_6ebfd006-dac-1
last commit: see git log
CI runs (image_run=39914488176, target=both, sha 82c7820): swipe-v1 39953020710 success; swipe-touch-v1 39953025217 success.
verified: zone baselines rebuilt from both runs (own scratch FW_CONSOLE_DIR per run) into results/faithful/runs; faithful.mjs verdict and lean regenerated; note updated.
MEASURED: control A'/A passes y04000, y04500, tail on both profiles; R fails y04000, y04500, tail on both profiles (same as freeze-run check).
done: (2) `<P>_control_<zone>` theorems in Measured.lean; (3) test/fidelity-compare.test.mjs in test:run.
open: lake check, measure-chromium test, runner land-inputs, ci-paths, fw land --dry through fw slot (see the report); lead lands.
Read first: research/notes/2026/10-2x-counts-font-fidelity.md (out-of-sample bullet), docs/team/handoffs/counts-font-fidelity.md
