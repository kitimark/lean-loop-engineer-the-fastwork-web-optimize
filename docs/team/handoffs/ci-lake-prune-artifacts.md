branch: worktree-wf_bd87ac67-917-1 (CI branch ci/ci-lake-prune-artifacts)
worktree: .claude/worktrees/wf_bd87ac67-917-1
last commit: see git log -1 (note + workflow prune step + this handoff)
CI runs: 40000273174 lean success (artifacts-only prune; the one allowed run is spent)
Verified: Lake treats a missing artifact as a MISS (Build/Common.lean:521-534, :579-614, Module.lean:731-751, 821-831). Run: cache dir 8.04 GB to 1.37 GB, blob 1806 MB restored vs 350 MB saved, rebuild without .lake/build 847 jobs in 1 s (1 Built line).
Item 2: 7 land legs table; item 3: rule is do not gate (note section "Follow-up 2026-10-24").
Open: first cross-runner restore of a pruned main entry (next main lean run that saves); the prune step is shipped in lean.yml without the TEMP rebuild and key suffix; cache evictions stay with the user.
Read first: research/notes/2026/10-2x-ci-setup-lean-slow.md, last section.
