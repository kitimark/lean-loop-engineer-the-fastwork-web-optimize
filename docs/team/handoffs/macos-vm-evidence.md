branch: worktree-wf_8b04760d-e7c-1 (CI branch ci/macos-vm-evidence at 315d7a10f, the code the green run used)
worktree: .claude/worktrees/wf_8b04760d-e7c-1
last commit: see git log; later commits only move the host-call op onto ci.telemetry (Lean + golden) and the land.ts read
CI runs: webkit-sim 40232220883 skipped (guard needs "[ci:webkit-sim]" in the head message); 40233131521 FAILED ("error: lsof: ETIMEDOUT" in startProxy, fixed by socketsWithin); 40234829295 SUCCESS at 315d7a10f (1 VM, 1 session, original arm, determinism; wrote v1-session-1.pass-1.part and .pass-2.part; telemetry line shows peak swap, compressor, pressure level)
paired runs for counts (original arm, 1 VM, main-side commit 3ead519e1): 40229095163, 40226715252, 40225058193. Layer counts at y=3000 (42), 4500 (47) and the final y (30) equal in all four; y=0 and y=1500 sit inside the baselines' own spread (106-116, 112-116). One new run only: "unchanged" is MEASURED on that run, INFERRED beyond it.

Phase 1 of macos-vm-evidence (harness and telemetry code only; workflows untouched).

Verified: Lean check.sh green; measure-webkit 850+ tests, ci-telemetry 18, ci-paths 56, runner land-inputs and ci-triggers 75.
- lean/Fw/Ci/Telemetry.lean: call bound, host stall, tick lag, 7 pressure fields; host-call questions are `ci.telemetry` requests with a `what` field (a second op name pushed Fw.Wire.ops over the init-cost bound).
- packages/measure-webkit: simctl async (sim.mjs runAsync), watchdog blocked-loop and running-call report, per-pass files, startProxy lsof retry; tests in test/host-call.test.mjs.
Trace of the four stalls: research/notes/2026/10-25-macos-vm-loss.md.

Open:
- Phase 2 workflow edits (after cross-pool-pooling and push-cycle-lag): upload out/$VM-session-$s.pass-*.part per pass; periodic upload of the telemetry probes.jsonl during the run (webkit-sim.yml, toolbar-throttle.yml).
- Writes outside the task: packages/measure-webkit/src/cli.mjs, packages/contracts/golden/ci/telemetry.jsonl (generated), apps/runner/src/land.ts (one read glob).
- Lost-VM cause UNKNOWN until a lost job leaves telemetry; job cap and load guard only after lost-VM data.
- Inspector command timeouts are not in the pending registry (inspector.mjs, poll.mjs).
- docs/team/tools/ci-telemetry.md may need a line on the new probe fields.
- TS stand-ins checked by golden replay: callBoundMs, callSettleMs, lagMs, tickBlocked; retryAsync against the Lean call golden; socketsWithin untested against Lean (no decision logic).

Read first: the research note, then packages/measure-webkit/src/sim.mjs (runAsync, pendingCalls).
