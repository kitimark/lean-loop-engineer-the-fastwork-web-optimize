branch: worktree-wf_6d63a3b2-2b5-1 (CI branch ci/one-chain-webkit)
worktree: .claude/worktrees/wf_6d63a3b2-2b5-1 (under the main checkout)
last commit: see `git log -1` (code commit f72a78731, note and handoff after it)
CI runs: none started by me (the counts and gate lanes need workflow inputs, so the lead dispatches them; see the note)

State
- Cause found: the first build ran the digits at their shared subscriber, before the scroll tick; the tick's first
  `window.scrollY` flushed the 10 face writes (2 updates, 330 elements, against 1 and 320). Lean `frameCost`,
  `frame499_faithful`, `frame499_atSubscriber`, `frame499_last`, `orderLast_eq_faithful` reproduce the counts exactly.
- Fix: `oneChainClock` (apps/site/src/parts/hero.countdown/driver.ts) re-queues its shared subscriber to the end of the
  shared set on the first visit of a frame and runs the chains on the second visit.
- Golden row `order499` regenerated from Lean; `oneChain.test.ts` replays it (276 hero.countdown tests pass).

Verified: lake build of the module, golden --check, vitest hero.countdown.
Open: WebKit counts base vs flag (3 runs each), Chromium swipe-touch-v1 base vs flag after the fix, breakpoint gate
both engines; commands in research/notes/2026/10-2x-one-chain-webkit.md. The scroll tick as the reader is INFERRED.
Read first: research/notes/2026/10-2x-one-chain-webkit.md, lean/Fw/Parts/HeroCountdownOneChain.lean (section "Where in
the frame the digits run").
