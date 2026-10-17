# Handoff: ci-webkit (make .github/workflows/webkit-sim.yml pass)

State: branch worktree-agent-aaceeac204ace4637, pushed as `ci/webkit-fix` (3 pushes used of 4). Read the commits first.

Causes found (CONFIRMED from run logs, artifacts via `gh run download <id> -n webkit-sim-v1`):
1. `tee out/...` ran before `out/` existed: workflow now `mkdir -p out`.
2. Slow runner (3 vCPU, host load 400-800, diagnosticd 80 % cpu): the first `simctl openurl` is dropped (0 tabs match, as on
   the Mac), a later `openurl` can block 77 s, the page target can take > 60 s, Runtime.evaluate/DOM.getDocument stall 15-60 s.
   All waits were fixed local values (15 s send, 4 s page target, 30 s tab).
3. A second inspector client takes the tab over (the proxy closes the first, code 1001): so a stale client is not the cause of
   "no page target" on the runner; it is Safari/webinspectord being slow after a reload. Reconnect still awaits the old close.
4. `merge` crashed ("reading 'cls'"): two sessions had different row sets (a `layers with reason (gone)` row appeared in one
   only) and rows were joined by index. Now rows use the union of reason names over all sessions and the key order is checked.

Changes (I/O glue only, no decisions): `src/timeouts.mjs` (`FW_WK_TIMEOUT_SCALE` multiplies every default wait, default 1;
`FW_WK_ATTEMPTS`, default 2), `reconnect()`/logged `openTab()` and awaited `close()` in `wip.mjs`, `onePassRetrying` and
`reasonNames` in `determinism.mjs`, tab asks loop in `session.mjs`. Workflow: scale 8, attempts 3, stderr kept as
`out/<vm>-session-N.log`, host state and logs uploaded always. Local defaults unchanged (`pnpm test` in
packages/measure-webkit: 37 pass with the main checkout's fwcore symlinked at lean/.lake/build/bin/fwcore).

Open items:
- Counts on the runner are taken under host load 400-800 (cpu idle 0 %): expect more "quarantined" classes than on a Mac;
  `load` stamps are in the session JSON. Do not read CI classes as engine nondeterminism before checking load.
- One session takes ~15-20 min on the runner (seek n=100 alone ~3 min); a run is ~45 min, job limit 90.
- The merge-row union is a TS stand-in for row alignment; the classification itself is still reduce.mjs (Lean spec pending).
