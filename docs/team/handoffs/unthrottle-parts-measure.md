Branch: worktree-wf_3b6992a9-795-1
Worktree: .claude/worktrees/wf_3b6992a9-795-1 (under the repo root)
Last commit: c0c5900cc (reducer, recorder, probe, cli, tests; handoff commit follows)
CI runs (toolbar-throttle lane, ci-only commit bd492dcf3 = yml edit, not on this branch):
- 40098348176 on ci/unthrottle-parts-measure-drags (mode drags, dispatch 1 of 3): success (6/6 usable passes per arm; hero verdict lifted; summary in results/unthrottle-parts/drags-40098348176.*)
- 40101695202 on ci/unthrottle-parts-measure-finish (dispatch 2 of 3): in_progress; job 3 failed at start (simctl list ETIMEDOUT, runner load, before any pass)
- 40101702393 on ci/unthrottle-parts-measure-rest (dispatch 3 of 3): in_progress; jobs 2 and 3 failed in the warm-up (no Safari tab, stall watchdog; load 562)
Verified: package tests 660 pass through the slot (incl. test/throttle-parts.test.mjs), scripts/ci-paths.test.mjs 56 pass, apps/runner land-inputs 60 pass.
Open: finish and rest results; the note; dry land; review ready.

## State
- src/throttle/parts.mjs reducer (twins reach/predicted; TS stand-ins: judge, bandFor cadence band, noData reasons, capture reversals).
- src/throttle/parts-recorder.mjs (page side, six series), parts-probe.mjs (modes drags|finish|rest), parts-cli.mjs (run|build-driver|report).
- The lane yml still runs throttle/cli.mjs with three arms. The CI branches carry an extra ci-only commit that points the run step at
  parts-cli.mjs with arms original,rewrite,lift,unthrottle, adds [throttle:rest] (3 rounds), longer timeouts, report via parts-cli.
  The permanent yml change is listed in the final report open[0] for the lead.
- A ci branch commit message must contain [ci:toolbar-throttle] and, for finish, [throttle:finish]; for rest, [throttle:rest].

## Read first
research/notes/2026/10-2x-unthrottle-parts.md (Lean predictions), research/notes/2026/10-2x-sim-finish-throttle.md (finish cadence), the golden throttle-parts.jsonl.
