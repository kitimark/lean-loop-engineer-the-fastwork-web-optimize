branch: worktree-wf_98d6c3e4-107-1 (push branch ci/combo-scroll-fight)
worktree: .claude/worktrees/wf_98d6c3e4-107-1 (under the main checkout)
last commit: (set at each commit)
CI runs: none yet
state: replay lane built and run locally once (debug, not a result): same-touch close-then-reopen reproduces the fight (reversals, jumps, 43 script writes) with the three morph.end bricks; new-touch reopens do not.
verified: replay metric tests (packages/measure-webkit/test/replay-combo.test.mjs).
open: bisect on CI, Lean composition model (lean/Fw/Parts/ComboScroll.lean), TS fix in morph.tween/end.logic.ts + driver.ts, golden + site test, after-fix replay, note, ledger row.
read first: packages/measure-webkit/src/replay/combo-*.mjs, .github/workflows/device-replay.yml job combo, apps/site/src/parts/morph.tween/end.logic.ts.
