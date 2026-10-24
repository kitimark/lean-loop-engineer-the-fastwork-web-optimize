branch: worktree-wf_6d63a3b2-2b5-1 (CI branch ci/one-chain-webkit)
worktree: .claude/worktrees/wf_6d63a3b2-2b5-1
last commit: see `git log -1`
CI runs (all on ci/one-chain-webkit at 9623493da): gate 40139523821 success; Chromium counts base 40139538524 success,
flag 40139529440 success; WebKit sim flag 40139526492 success (n=1), base 40139511311 failed (VM timeout, n=0).

State
- Fix (digits last) is in; Lean frameCost theorems stand; golden order499 replays.
- Chromium post-fix: flag +1 update in 157/771 swipe frames (3/3 runs), FireAnimationFrame -314. Verdict trade.
  The profile changed, so frame 499 is not comparable; the causal check is not delivered.
- WebKit: base has no usable VM; verdict open. Re-dispatch the base (lead):
  pnpm -s fw run --target rewrite --engines webkit --runs 3 --ref ci/one-chain-webkit
Read first: research/notes/2026/10-2x-one-chain-webkit.md (section Post-fix runs).
Follow-up: choose the digits' order per frame kind from a trace, or revert to the subscribe position.
