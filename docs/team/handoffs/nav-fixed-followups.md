branch: worktree-wf_cad36a29-020-1
worktree: .claude/worktrees/wf_cad36a29-020-1 (repo-relative)
last commit: see git log (final)
CI branches: ci/nav-fixed-followups 6f35ba80a (trajectory fw=nav:clip-box), ci/nav-fixed-followups-bar 19b301f45, ci/nav-fixed-followups-logo 4503e6d66.
Runs, all complete: per-flag gates (both engines, 6f35ba8) clip-box 39857031808, bar-fixed 39860402069, logo-3d 39862686589, all PASS. trajectory-probe verdict runs clip-box 39856949244, bar-fixed 39856971788, logo-3d 39856990203. webkit-sim default 39864122924, bar-fixed 39865290039, logo-3d 39865284565 (success); clip-box 39865298847 failed (simulator lost Safari, infra). chromium-counts swipe-v1 x3: default 39865294590, logo-3d 39865303675. Budget of 9 dispatches used.
Verified: restW takes h; decl_eq_rest_zero/decl_close_rest/used_eq_rest_one for every h; ledger rows corrected and numbers added; check.sh green at d56e71b; runner and ci-paths tests green.
Findings: no cost number moves (Chromium counts and WebKit census equal to default within spread); trajectory nav-clip cell cannot grade a flag on main (cells step has no --search); Chromium trajectory new units are by design (union box).
Open (lead): webkit-sim lag=true cost=on for three flags; webkit-sim clip-box rerun; chromium-counts clip-box and bar-fixed; --search on the cells step of trajectory-probe.yml.
Read first: research/notes/2026/10-2x-nav-fixed-size.md section Follow-ups; results/nav-fixed-size/.
