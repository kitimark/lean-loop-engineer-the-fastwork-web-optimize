branch: worktree-wf_6d63a3b2-2b5-1 (CI branch ci/one-chain-webkit, pushed at f74e3313a)
worktree: .claude/worktrees/wf_6d63a3b2-2b5-1
last commit: see `git log -1` (round 2 = f74e3313a plus the handoff/merge commit)
CI runs: none started by me in round 2 (all need lead inputs). Round-1 runs (digits-last build, now reverted): gate 40139523821
success; Chromium base 40139538524, flag 40139529440 success; WebKit flag 40139526492 (n=1), base 40139511311 failed (n=0).

State (round 2)
- Lean: kinds kind499 / kindEarly, orders faithful / atSubscriber / last, theorems frame499_*, early_*, extra_updates,
  no_fixed_order (lean/Fw/Parts/HeroCountdownOneChain.lean). Golden row `orders` regenerated; oneChain.test.ts replays it.
- Decision: no fixed order wins both kinds; variant reverted to the subscribe position (driver.ts, part.json, footprint).
- Site tests and typecheck pass. Chromium delta at the subscribe position (old runs, local analysis): +1 update in 1 of 531
  frames (frame 499), FireAnimationFrame -252.
Open (lead dispatches on ci/one-chain-webkit at f74e3313a)
- pnpm -s fw run --target rewrite --engines chromium --profile swipe-touch-v1 --runs 3 --ref ci/one-chain-webkit [--fw hero.countdown:one-chain]
- pnpm -s fw run --target rewrite --engines webkit --runs 3 --ref ci/one-chain-webkit [--fw hero.countdown:one-chain]
- pnpm -s fw run --gate --engines both --fw hero.countdown:one-chain --ref ci/one-chain-webkit
Read first: research/notes/2026/10-2x-one-chain-webkit.md.
