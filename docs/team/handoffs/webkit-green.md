# Handoff: webkit-green (webkit-sim passes on CI, standard xcode-27 runner only)

State: branch worktree-agent-aa1718b605d9cb1b4, pushed as `ci/webkit-green` (2 pushes). Read the two commits (Task: webkit-green).
No paid runner used or planned (user decision 2026-10-17: never).

Changes (I/O glue only, no decisions):
- `src/poll.mjs` (new): `pollUntil`, `ensureTab`, `attachFresh`, `retryWhile`, injectable clock.
- session.mjs: the `sleep(T(3000))` is gone; openurl once, start the proxy, then `ensureTab` re-sends openurl every 6 s while
  no tab is listed (deadline T(30000)); stops asking once a tab is listed.
- wip.mjs: `reconnect` has no fixed pause (close awaited, then openTab polls); `navigateTab` marks the old document
  (`window.__fwNav`) and `attachFresh` releases clients that attached to the old one, then waits for readyState complete.
- sim.mjs `phoneIds`: timeout T(15000), a timeout is asked again (3 tries); ENOENT = no phones; real failure still fails closed.
- Workflow: push default sessions=1 (dispatch can ask for 2); merge job downloads with `merge-multiple: true` (a single
  matching artifact has no subdirectory, so the glob matched nothing: run 39046570019 merge failed for that reason only).
- Not done (lever 5): Safari relaunch between sessions is kept (determinism choice, sim.mjs:86); no keep-Safari flag added.
- Tests: test/poll.test.mjs (fake clock; one test per replaced sleep, openurl resend, idevice_id retry). 36 pass; the 2
  fwcore tests need the Lean binary and fail in a bare worktree.

CI results (standard xcode-27, 1 VM, 1 session = 2 passes, scale 8, attempts 3):
- 39046570019 (cb008b5): sim job success 21 min 54 s; merge failed (workflow glob bug, fixed in the next commit).
- 39048376821 (bf023e4): all green, sim job 19 min 1 s; classes 57 deterministic / 11 stable / 36 quarantined (host load ~970).
- 39050061299 (workflow_dispatch of bf023e4, defaults): all green, sim job 24 min 18 s. Two consecutive green runs with classes.
- Before: 1-session passes were not isolated; 2 sessions took 33-43 min healthy, and session 2 stalled in earlier runs.
- The first openurl was dropped again in both runs; the resend landed after 6 s (run 2: asks at 6, 56, 88 s) or 8 s / 30 s.

Open items: 2 sessions per VM is untested with the new code (dispatch `sessions=2` to try); quarantined classes are
dominated by host load 900+, not engine nondeterminism (load stamps are in the session JSON).
