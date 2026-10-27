Branch: worktree-wf_2ebef0df-5ee-1 (CI branch ci/geom-style-cut)
Worktree: .claude/worktrees/wf_2ebef0df-5ee-1 (under the main checkout)
Last commit: 295c32121 (CI 2, the cut). Pushes used: 2 of 3 (CI 1 at 2d7ba227b was an empty commit: skipped by the guard, "0 files differ from main").

## CI runs (sha 295c32121, the cut)
- chromium-counts 40589409521 (swipe-touch-v1, runs=3, arms morph.geom:on | morph.geom:on,morph.tween:geom-timed): in progress
- breakpoint-gate 40589409628 (flip-cell graded, flip-verify): in progress
- lean 40589409389: in progress
- Before (CI 3, not yet pushed): revert driver.ts and index.tsx of morph.tween on a commit, same counts line, push, then re-apply the cut locally (no push).

## Verified
- Lean lean/Fw/Parts/MorphStyle.lean (seen_same, base_writes, leave_writes, skip_iff, skippable_*), golden packages/contracts/golden/parts/morph-style.jsonl, wired in Fw.lean, check.sh, Trigger.lean, triggers.jsonl.
- TS apps/site/src/parts/morph.tween/{style.logic.ts,style.golden.test.ts,style.probe.test.ts}; driver.ts updateFade and index.tsx publish use writes(flip, m); env.flip only when morph.geom is on.
- Probe (jsdom, deterministic): results/geom-style-cut/writes.json: 3 writes/frame (base) -> 1 (flip, data-fw-morph).
- vitest apps/site 165 files pass; footprint regenerated.

## Open
- WebKit Simulator counts: webkit-sim push carries no fw; needs a dispatch by the lead.
- Chromium 6x throttle and phone: not in this lane.
- Research note, ledger notes, check.sh via slot, review ready, dry land: not done yet.
