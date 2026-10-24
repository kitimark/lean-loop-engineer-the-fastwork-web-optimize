# throttle-lift-ship handoff

Branch: worktree-wf_1b734b7c-35a-1 (CI branch ci/throttle-lift-ship). Worktree: .claude/worktrees/wf_1b734b7c-35a-1 (under the repo root)
Last commit: see `git log -1` (first CI push carried the baseline lanes).

CI runs (id, state): none yet (first push pending).

Verified: Lean module `lean/Fw/Parts/EngineScrollUnthrottle.lean` compiles (condition chain, same look, cost bound, generated CSS);
golden `packages/contracts/golden/parts/engine.scroll.unthrottle.jsonl`; TS `unthrottle.ts` + test against it.
Open: check.sh and site tests via slot, baseline push lanes, three `fw run` dispatches (chromium counts, webkit sim, gate), note,
ledger rows, preset proposal.
