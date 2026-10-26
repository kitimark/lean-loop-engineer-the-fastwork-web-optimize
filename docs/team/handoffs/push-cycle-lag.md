branch: worktree-wf_d4bb5016-cf9-1 (CI branch ci/push-cycle-lag, head 3cd4f2abf)
worktree: .claude/worktrees/wf_d4bb5016-cf9-1 (under the main checkout)
last commit: see git log (merge of main after "push-cycle-lag: flag-off table from push 3b")
CI runs: 40206864819 failure (push 1 sim 2 lost), 40206864910 success, 40206864857 success, 40218625611 success, 40218625602 success, 40232266467 failure (upload colon bug), 40242079617 toolbar-throttle success (push 3b, flag-off, 11 of 12 passes; off-morph 2 of 3). No further pushes.
verified: push 3b reduced (results/push-cycle-lag/webkit-d1000-flagoff-run40242079617.md), note section "Flag-off pages"; none of the three flag-off pages loses the rise (Lean trend rises for all four incl. control), so no flag is the cause; engine.scroll:unthrottle off is worse. Ledger notes added for engine.scroll:unthrottle and morph.countdown:strip.
open: H2 now open for the composition (flips between runs); H4 premise only; WebKit layer count / pass-clock separation are follow-ups (note, fix candidates 2b).
state: Lean PushCycle.lean + golden push-cycle.jsonl; WebKit lane packages/measure-webkit/src/throttle/push-cycle*.mjs; Chromium lane packages/measure-chromium/src/push-cycle.mjs; phone profiles results/push-cycle-lag/phone-profile-d*.json.
conventions: plain single shell commands; checks through pnpm -s fw slot run; triggers.jsonl regenerated from Lean (lake test -- --write-ci-trigger-golden) after merging main.
read first: research/notes/2026/10-2x-push-cycle-lag.md, this file.
