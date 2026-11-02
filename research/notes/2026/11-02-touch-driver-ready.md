---
id: 2026-11-02-touch-driver-ready
kind: note
title: "Why the CI Simulator touch driver sometimes has no ready file: the launch stalls before the test body, a relaunch recovers it; the stop kill this branch added broke restarts and is removed"
status: review
created: 2026-11-02
topics: [webkit, simulator, xcuitest, touch, ci, measure]
---

# Touch driver ready: cause, Lean decisions, fix, two CI runs

Task `touch-driver-ready`. Before: run `41369102226` (4 of 12 jobs "no ready file after 240 s") and run `41380162402`
(6 of 12 at 480 s). After: runs `41391781282` (dispatch 1) and `41402584809` (dispatch 2), both `smoothness`, 12 touch-lock
simulator jobs, branch `ci/touch-driver-ready`. The Simulator is not the phone.

## Answer

- **A first-start fault is a driver launch that never reaches the XCUITest body (MEASURED).** In run `41402584809` five
  first launches (jobs 2, 6, 8, 10, 11) wrote no `alive` file in 150 s. `alive` is the test body's first step. Their
  log tails stop at different points before it: job 8 at the IDESchemeActionSDKRecord line, job 6 at the runner's "Running
  tests...", job 11 at "Test Suite 'PushServer' started" with no test case; jobs 2 and 10 have no tail. `ps` timed out after
  15 s in jobs 2, 6 and 10; in jobs 8 and 11 it shows the Simulator runtime at 47 to 64 % CPU and `diagnosticd` at 33 %.
  A launch that works writes `alive` after 39 to 126 s and `ready` 1 to 3 s later (11 of
  11 first starts in run `41391781282`, 9 of 9 working launches in run `41402584809`), so Safari is not the slow part.
- **A relaunch recovers most of them (MEASURED).** Launch 1 failed in 5 of 10 jobs; launch 2 or 3 became ready in 4 of those 5
  (65 to 77 s after its start). Per launch about half become ready (9 of 18). Only job 2 failed all three launches and ended
  `touch-driver-not-ready`. Per-job ready driver at the first start: 9 of 10 (was 7 of 11 in `41369102226` and 10 of 12 in `41380162402`). The first-start rate did not improve against `41380162402` (10 of 12 before, 9 of 10 after); the 4 of 5 recovered stalls show the relaunch works.
- **The fault rate is not constant across runs (MEASURED).** Launch 1 failed in 0 of 11 jobs in run `41391781282` and 5 of 10 in
  `41402584809`. Run 1 therefore cannot show that the relaunch works; run 2 does.
- **Restarts: the stop kill this branch added is the likely cause of 0 of 8 ready (MEASURED, cause INFERRED).** Restarts became
  ready in 0 of 8 on this branch's earlier commits, which killed the driver at every stop (`driver-stop-killed`: 8 of 8 stops
  in `41402584809`, every stop in `41391781282`; ready 0 in `41391781282` jobs 1, 2, 5, 7, 8, 9 and `41402584809` jobs 3, 12),
  and in 5 of 9 on main's stop path, which never kills (`41369102226` job 2 at 220 s, 1 of 2 decided; `41380162402` jobs 2, 10, 3,
  9 at 74, 141, 176, 178 s, 4 of 7 decided). So the restart failure was new on this branch, not old, and the 470 s launch cap
  is justified only because main's 74 to 220 s restarts finished without the kill. The kill is removed: `stopServer` now
  writes the stop file, waits up to 20 s, removes the directory with no kill, and sets `server.stopFault` to the named fault
  `driver-stop-late` when the driver did not exit in time. Restart readiness after this change is INFERRED to match main's;
  no CI dispatch is left, so a CI confirmation is a follow-up. `restartCfg` keeps one 470 s launch (main waited 480 s).
- **The final stop often does not exit in 20 s (MEASURED, reason unknown).** 8 of 8 stops in `41402584809` and every stop in
  `41391781282` outlasted 20 s (then killed). Not explained: slow xcodebuild teardown or a hung test thread. Now only named
  `driver-stop-late`.
- **Job 1 of `41402584809` (outside this unit).** Its first start was ready at 56 s; it ended INCOMPLETE after 6 windows: walk
  hard stop, inspector dead, and `simctl shutdown failed; exit code 4`.

## Before and after

| Run | Jobs with data | First start ready | Launch 1 stuck | Relaunch recovered | First start not ready | Restarts failed |
|---|---|---|---|---|---|---|
| `41369102226` (240 s, old) | 11 (job 4 no artifact) | 7 | not recorded | none | 4 (jobs 3, 7, 8, 12) | 1 of 2 decided (job 11; job 2 ready at 220 s) |
| `41380162402` (480 s, old) | 12 | 10 | not recorded | none | 2 (jobs 5, 7) | 3 of 7 decided (jobs 3, 4, 11; jobs 2, 3, 9, 10 ready at 74, 176, 178, 141 s) |
| `41391781282` (3 x 150 s) | 11 (job 12 hard stop) | 11 | 0 | 0 of 0 | 0 | 6 of 6 |
| `41402584809` (3 x 150 s, restart 1 x 470 s) | 10 (jobs 7, 9 no artifact and no log) | 9 | 5 | 4 of 5 | 1 (job 2) | 2 of 2 decided |

Run 2 tally (`touchlock-cli launches`): jobs 10, ready 9, first try 5, relaunched 5, `driver-launch-stuck` 9, `driver-body-stuck` 0,
`driver-ended` 0. Job 12 is its retry artifact (`smoothness-webkit-sim-12-retry`); job 5 uploaded; jobs 7 and 9 have no
artifact and the job log is "not found", so they are not counted.

## What changed

- **Lean** `lean/Fw/Measure/TouchReady.lean`: `verdict` (ready, wait, relaunch, give), `replay`, `stopStep`, `tally`, `cfg`
  (3 launches of 150 s, kill 10 s, stop wait 20 s) and `restartCfg` (1 launch of 470 s). One theorem per OR-branch:
  `verdict_cases`, `ready_wins`, `wait_iff`, `relaunch_cap`, `give_cap`; fit in the 480 s allowance: `worst_fits`, `run_fits`,
  `restart_fits`, `restart_run_fits`; `restart_never_relaunches`; `stop_*`, `tally_*`. Golden
  `packages/contracts/golden/measure/touch-ready.jsonl` (38 lines).
- **TS** `packages/measure-webkit/src/touch-ready.mjs` replays the golden; `touch-push.mjs` `startServer` relaunches a cut launch
  with a fresh directory and names `driver-launch-stuck`, `driver-body-stuck` or `driver-ended`; `stopServer` is main's stop path (stop file, wait up to 20 s, remove the dir, no kill) and
  sets `driver-stop-late` when the driver did not exit in time. The Swift tests write `alive` when the body starts.
- No retry hides a failure: every cut launch is in `touch.launches` of `touch-lock.json` with its fault, `ps` top and log tail.

## Stop path against main

`git diff main -- packages/measure-webkit/src/touch-push.mjs`, `stopServer` body: main races `server.run.exited` against
`sleep(20000)`; this branch loops `stopStep` (Lean `TouchReady`, golden-checked) until exit or 20 s. Both write the `stop`
file first and end with the optional log copy and `rmSync(server.dir)`; neither kills.

```
-  await Promise.race([server.run.exited, sleep(20000)]);
+  const w0 = Date.now();
+  let exited = false;
+  server.run.exited.then(() => { exited = true; }, () => { exited = true; });
+  for (;;) {
+    const step = stopStep(cfg, exited || server.run.state.ended, Date.now() - w0);
+    if (step === 'clean') break;
+    if (step !== 'wait') { server.stopFault = step; break; }   // 'driver-stop-late', no kill
+    await Promise.race([server.run.exited, sleep(100)]);
+  }
```

The loop differs from main by the named fault (`stopFault`) and by polling `run.state.ended` as well as the exit promise.

## Verdict on the pinned unit

- Cause with log evidence: launch never reaches the test body (MEASURED above); the reason the Simulator host stalls there
  is INFERRED load (Simulator runtime and `diagnosticd` busy).
- Deterministic fix: relaunch at 150 s works for first starts (4 of 5 stalls recovered). The restart failure was ours (the stop kill), now removed; restart readiness afterwards is INFERRED, not measured.

## Follow-ups (not in this task)

- Restart: one CI run (12 jobs) to confirm restarts become ready again without the kill (expect about 5 of 9 as on main).
  Why a stopped driver outlasts 20 s is separate.
- First start: per-launch success is about 50 %, so 3 launches leave about 12 % failing (1 of 10 seen). A 4th launch needs more
  than the 480 s allowance; `alive` was written by 126 s at the latest, so a launch cap near 135 s would fit 3 launches plus
  one more but leaves no margin on the slow ones.
- Why the stop never exits in 20 s.

## Accepted limits

Free GitHub macOS runners (5 slots); two dispatches used of two; faults named, never retried to a pass; the Simulator is not the
phone; jobs 7 and 9 of run 2 and job 12 of run 1 are missing data.
