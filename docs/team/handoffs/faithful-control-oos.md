branch: worktree-wf_6ebfd006-dac-1 (CI branch ci/faithful-control-oos)
worktree: .claude/worktrees/wf_6ebfd006-dac-1
last commit: see git log (item 2 and 3 committed; handoff commit follows)
CI runs: none yet. Item (1) waits for the lead's dispatches (below); no run id exists.
verified: lake check green (lean/scripts/check.sh via fw slot) with the per-zone control theorems; measure-chromium faithful.test + fidelity-compare.test pass (13).
done: (2) faithful.mjs lean emits `<P>_control_<zone>` theorems (pass = <bit> and failed = [...] of zoneVerdict tbl A C z) for every profile with a comparable control; Measured.lean regenerated, currently all control zones pass=true. (3) test/fidelity-compare.test.mjs is in package.json test:run. test in faithful.test.mjs pins the theorems.
open: (1) dispatch (lead), one target=both run per profile on image_run=39914488176, runs=3 (default):
  gh workflow run chromium-counts.yml --ref ci/faithful-control-oos -f profile=swipe-v1 -f target=both -f image_run=39914488176
  gh workflow run chromium-counts.yml --ref ci/faithful-control-oos -f profile=swipe-touch-v1 -f target=both -f image_run=39914488176
after the runs (resume with the two run ids): `pnpm -s fw ci <run> --branch ci/faithful-control-oos` per run (store keeps one run per key: pull each into its own scratch FW_CONSOLE_DIR), then
  node packages/measure-chromium/src/zone-baseline.mjs --store <store> --target rewrite|original --profile <p> --run <id> --out results/faithful/runs
  node packages/measure-chromium/src/zone-baseline.mjs baseline --out results/faithful/runs --profile <p> --target rewrite|original
  node packages/measure-chromium/src/faithful.mjs verdict ; node packages/measure-chromium/src/faithful.mjs lean ; lake check ; update research/notes/2026/10-2x-counts-font-fidelity.md
  (runs/ is replaced by the out-of-sample files; the freeze-run files stay in git history; A stays the frozen baselines)
Read first: docs/team/handoffs/counts-font-fidelity.md
