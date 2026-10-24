Branch: worktree-wf_bbd9b85f-6e4-1 (CI branch ci/earn-webkit-smooth). Worktree: .claude/worktrees/wf_bbd9b85f-6e4-1. Last sha: `git log -1`.
CI runs: 40100235090 trajectory-probe FAILED (fixed); 40100235131 lean failed (fixed); 40100783726 trajectory-probe ok; 40100783656 breakpoint-gate ok (default page); 40100783678 lean ok; 40102193302 trajectory-probe ok; 40102193331 lean ok;
40106804693 gate with variant FAILED (raw lists, fixed by normalization); 40111361865 gate with variant FAILED (reduced-motion: the variant's earn rules outranked the original's transition: none). 40114684690 gate with variant on both engines on head 27020e909: SUCCESS (every job).
Reduced-motion round: Lean NavEarnWebkit.reduced_started_empty / reduced_computed_faithful, golden rows `reduced`, site test earn.webkit.golden.test.ts; nav.module.css variant rules moved into the no-preference block with :not(.is-earn-still); trajectory table/golden/reduce.mjs/test updated for the new lines.
Lead dispatch: gh workflow run breakpoint-gate.yml --ref ci/earn-webkit-smooth -f engines=both -f fw=nav:earn-logical
Open: user Safari/iPhone review (ledger n=73); third macOS job follow-up.
Read first: research/notes/2026/10-2x-earn-webkit-smooth.md.
