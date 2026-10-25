branch: worktree-wf_8b04760d-e7c-1 (CI branch ci/macos-vm-evidence = same commit)
worktree: .claude/worktrees/wf_8b04760d-e7c-1
last commit: 2dba3ad9e plus the main merge (handoff commit follows)
CI runs: push 1 webkit-sim 40232220883 skipped (guard needs "[ci:webkit-sim]" in the head commit message); push 2 webkit-sim 40233131521 FAILED at 2b1ea36c1 (Determinism sessions "error: lsof: ETIMEDOUT" in startProxy, 30 s lsof on a starved host, pressure level 2; the new telemetry line printed peak swap 121 MB, compressor 1415 MB); push 3 (last allowed) webkit-sim 40234829295 in_progress at 315d7a10f, after the startProxy lsof retry (2dba3ad9e)
paired run for counts: none yet named; counts are not changed by construction (the async layer only changes how simctl is called), golden replay covers the new decisions

Phase 1 of macos-vm-evidence (harness and telemetry code only; workflows untouched).

Verified (local tests, not results):
- Lean: lean/Fw/Ci/Telemetry.lean (call bound, host stall, tick lag, 7 pressure fields; op ci.hostCall; golden packages/contracts/golden/ci/telemetry.jsonl regenerated).
- scripts/ci-telemetry: swap, compressor, memory_pressure readings with tests (18 pass).
- packages/measure-webkit: simctl async via sim.mjs runAsync (bound = Lean callBoundMs, settle = bound + 5 s), watchdog reports blocked loop and running host calls, per-pass files out/<x>.pass-N.part, tests in test/host-call.test.mjs (17 pass).

Trace of the four Determinism-session stalls: research/notes/2026/10-25-macos-vm-loss.md.

Open:
- Phase 2 workflow edits (wait for cross-pool-pooling and push-cycle-lag): upload out/$VM-session-$s.pass-*.part per pass; periodic upload of the telemetry probes.jsonl during the run (webkit-sim.yml, toolbar-throttle.yml).
- Out-of-scope writes: packages/measure-webkit/src/cli.mjs (one call to writePassFile), packages/contracts/golden/ci/telemetry.jsonl (generated).
- Lost-VM cause UNKNOWN until a lost job leaves telemetry; job-length cap and Lean load guard only after lost-VM data.
- Inspector command timeouts are not in the pending registry (inspector.mjs, poll.mjs out of scope).
- docs/team/tools/ci-telemetry.md may need a line about the new probe fields.
- TS stand-ins checked by golden replay: callBoundMs, callSettleMs (sim.mjs), lagMs, tickBlocked (watchdog.mjs); retryAsync checked against the Lean call golden.

Read first: the research note, then packages/measure-webkit/src/sim.mjs (runAsync, pendingCalls).
