# watch-cli handoff
State: `fw watch` done on branch worktree-wf_33b3c584-8ee-2 (see git log). Lean branch ...-1 (obs.health) merged in.
Files: apps/runner/src/watch.ts (CLI, render, fwcore call, loop), src/watch-collect.ts (collectors, pure parsers),
test/watch.test.ts (9 tests, fixtures built in a temp dir), docs/team/tools/watch.md, one dispatch line in src/fw.ts.
Conventions: no decision in TS; the only classification in collectors is the memory level (sysctl number -> enum) and
the SCOPE rule (24 h ghost, 1 h done window). Output holds names/counts/times only.
Open: (1) fwcore with obs.health is not in the main build yet; coreCandidates() falls back to sibling worktrees.
(2) Other runner tests (spawn-guard, land) need a built fwcore and fail without it here. (3) Teammates idle on purpose
read as stalled. (4) Spool has no pre-tool event, so in-flight comes from transcripts only (no verb).
Read first: docs/team/tools/watch.md.
