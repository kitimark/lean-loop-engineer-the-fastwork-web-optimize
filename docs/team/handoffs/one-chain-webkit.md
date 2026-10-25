branch: worktree-wf_6d63a3b2-2b5-1 (CI branch ci/one-chain-webkit, head f74e3313a)
worktree: .claude/worktrees/wf_6d63a3b2-2b5-1
last commit: see `git log -1`
CI runs (all on f74e3313a, no new push): Chromium swipe-touch-v1 base 40153927556 success, flag 40153920231 success;
WebKit Simulator base 40153925235 success (3 VMs), flag 40153917806 failure (r1 CoreSimulator 405; r2, r3 ok, n=2);
gate both engines with the flag 40153922711 success (all pass; webkit 2 unreachable widths per row, none failing).

State
- Lean (round 2): frame kinds, no_fixed_order, extra_updates; variant at the subscribe position; golden `orders` replayed.
- Counts reduced to results/one-chain-webkit/summary.json; reducer script was scratch (not committed).
- Chromium: UpdateLayoutTree +283 (+11.8 %), elements equal, FireAnimationFrame -314 (-12.2 %): trade (MEASURED).
  The extra update lands in 30 % of frames, so Lean early_atSubscriber is falsified for the current base (kind fitted).
- WebKit: RecalculateStyles 672.3 vs 671.8, Layout inside spread, no-win.
Task closed as a finding (round 2 review); variant code path unchanged.
Open
- Follow-ups: TS stand-in frameCost in oneChain.test.ts stays; model the shared loop's real registration order per frame (outside the unit).
Read first: research/notes/2026/10-2x-one-chain-webkit.md (sections Round-2 runs, Verdicts).
