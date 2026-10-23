branch: worktree-wf_97f1e0e7-814-1 (CI branch ci/ci-lake-cache-fresh)
worktree: .claude/worktrees/wf_97f1e0e7-814-1
last commit: see `git log -1` (note + this handoff; workflow changes reverted)
CI runs: 39984856000 lean success (prune + sizes, exact key hit, no save); 39985377389 lean success (prune, rebuild from pruned cache, 423 s). Land legs read: 39979064402, 39980374766, 39982378759, 39986375659.
Verified (MEASURED): naive prune `-links 1 -delete` cuts 6.84 GB to 1.37 GB but the next build rebuilds all (837 lines, 423 s), so it is NOT shipped; a land leg after a fresh main entry built 7 modules in 7-9 s vs 57-76 modules in 74-100 s on a 74-97 min old entry; 6 never-restored ci/* lake entries = 7.80 GB.
Open: refined prune (artifacts/ only, keep outputs/) needs one more lean.yml run; eviction rule is a proposal for the user (no cache deleted).
Read first: research/notes/2026/10-2x-ci-setup-lean-slow.md, section "Follow-up 2026-10-23".
