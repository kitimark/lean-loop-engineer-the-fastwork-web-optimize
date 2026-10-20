# Handoff: gh-budget-waiter-liveness

Round 2 done (TZ-pinned token + cross-process test, recorded-but-unreadable is dead, lock order tested on both sides, no $$ in new docstrings).
State: branch worktree-wf_a53a82a4-042-1, commit in the report. Lean (Budget.lean, Wire.lean, Golden.lean) and TS done.

Verified: `sh lean/scripts/check.sh` green; `pnpm test` in packages/gh-budget (52 pass, tsc clean); `node --test
scripts/ci-paths.test.mjs` (41 pass); apps/runner `pnpm test` (1390 pass).

What it does: a watch is kept exactly while its waiter lives. Marker `{pid, start}` (start = `ps -o lstart=`). `ci.budget.next`
takes `markers`; fwcore `sweep`s watches without a live marker (`orphan` incident) before `createdSince`.

Conventions: TS only reads facts (packages/gh-budget/src/waiters.ts); the verdict is `Marker.alive` in Lean. Marker write and
`register` share one state lock (`addWaiter`); the poller reads the dir under the lock of its decision. Replays use `addWaiter`
so each watch has a live marker.

Open: start token resolution is one second (stated limit); no real-SIGTERM process test for `onSig`; `dropWaiter` keeps a
pid-only refcount shortcut and marker reaping (follow-ups); a dropped waiter learns of the drop only at its timeout.

Read first: research/notes/2026/10-20-gh-budget-waiter-liveness.md, lean/Fw/Ci/Budget.lean section (j),
packages/gh-budget/src/waiters.ts, packages/gh-budget/test/waiter-liveness.test.ts.
