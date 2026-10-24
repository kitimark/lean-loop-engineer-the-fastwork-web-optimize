branch: worktree-wf_98d6c3e4-107-1 (push branch ci/combo-scroll-fight)
worktree: .claude/worktrees/wf_98d6c3e4-107-1 (under the main checkout)
last commit: 510e82050 (branch worktree-wf_98d6c3e4-107-1, pushed as ci/device-replay; the workflow only triggers on that branch name)
CI runs: 40128362520 failed (build step: morph.countdown:strip needs hero.countdown:strip; arms fixed); 40129128571 device-replay running (before/after, push 3 of 4); lean 40129128528 running
state: replay lane built and run locally once (debug, not a result): same-touch close-then-reopen reproduces the fight (reversals, jumps, 43 script writes) with the three morph.end bricks; new-touch reopens do not.
verified: replay metric tests (packages/measure-webkit/test/replay-combo.test.mjs).
open: bisect on CI, Lean composition model (lean/Fw/Parts/ComboScroll.lean), TS fix in morph.tween/end.logic.ts + driver.ts, golden + site test, after-fix replay, note, ledger row.
read first: packages/measure-webkit/src/replay/combo-*.mjs, .github/workflows/device-replay.yml job combo, apps/site/src/parts/morph.tween/end.logic.ts.
