branch: worktree-wf_cad36a29-020-1
worktree: .claude/worktrees/wf_cad36a29-020-1 (repo-relative)
last commit: see git log (checkpoint 2, after gates and trajectory)
CI branches: ci/nav-fixed-followups 6f35ba80a (fw=nav:clip-box), ci/nav-fixed-followups-bar 19b301f45, ci/nav-fixed-followups-logo 4503e6d66.
Runs (complete, success):
- trajectory-probe verdict runs, engines both: clip-box 39856949244, bar-fixed 39856971788, logo-3d 39856990203 (inputs read from trajectory-inputs).
- per-flag breakpoint gates, both engines, on ci/nav-fixed-followups 6f35ba8: nav:clip-box 39857031808, nav:bar-fixed 39860402069, nav:logo-3d 39862686589 (all PASS).
Dispatched (running, 6 of 9 budget used after the 4 webkit and 2 chromium below; total 9 with gates): webkit-sim rewrite default / nav:clip-box / nav:bar-fixed / nav:logo-3d; chromium-counts swipe-v1 x3 default and nav:logo-3d. Ids: read `gh run list --branch ci/nav-fixed-followups`.
Finding: the trajectory cells step on main runs `cells-gpu-cli.mjs run` with no --search, so the nav-clip cell grades the default rewrite (search=(default), E for all) not the flag; the per-flag nav-clip grade is undelivered until the step passes --search "$SEARCH" (workflow, not in this task's writes).
Trajectory units (chromium, new vs faithful): clip 370, bar 415, logo 659, all by design (nav.rect, nav.border-radius, logo.rect-in-nav differ: union box). WebKit hero path CLEAN x3.
Lean: restW takes h; decl_eq_rest_zero/decl_close_rest/used_eq_rest_one for every h; check.sh green.
Artifacts: results/nav-fixed-size/traj-{clip,bar,logo}/.
Open: census/cost numbers, note tables, ledger numbers, dry land.
