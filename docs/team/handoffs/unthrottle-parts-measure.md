Branch: worktree-wf_3b6992a9-795-1
Worktree: .claude/worktrees/wf_3b6992a9-795-1 (under the repo root)
Last commit: c0c5900cc (reducer, recorder, probe, cli, tests; handoff commit follows)
CI runs (toolbar-throttle lane, ci-only commit bd492dcf3 = yml edit, not on this branch):
- 40098348176 on ci/unthrottle-parts-measure-drags (mode drags, dispatch 1 of 3): in_progress
Verified: test/throttle-parts.test.mjs 26 pass locally (golden consts, reach 9/9/5, predicted vs key lines, example runs/band/maxStep, recorder in a vm sandbox, synthetic passes). Not yet through the slot.
Open: dispatch 2 (finish) and 3 (rest); the note; results/unthrottle-parts; dry land; review ready.

## State
- src/throttle/parts.mjs reducer (twins reach/predicted; TS stand-ins: judge, bandFor cadence band, noData reasons, capture reversals).
- src/throttle/parts-recorder.mjs (page side, six series), parts-probe.mjs (modes drags|finish|rest), parts-cli.mjs (run|build-driver|report).
- The lane yml still runs throttle/cli.mjs with three arms. The CI branches carry an extra ci-only commit that points the run step at
  parts-cli.mjs with arms original,rewrite,lift,unthrottle, adds [throttle:rest] (3 rounds), longer timeouts, report via parts-cli.
  The permanent yml change is listed in the final report open[0] for the lead.
- A ci branch commit message must contain [ci:toolbar-throttle] and, for finish, [throttle:finish]; for rest, [throttle:rest].

## Read first
research/notes/2026/10-2x-unthrottle-parts.md (Lean predictions), research/notes/2026/10-2x-sim-finish-throttle.md (finish cadence), the golden throttle-parts.jsonl.
