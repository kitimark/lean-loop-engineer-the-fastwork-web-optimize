# Handoff: webkit-sim-failfast, round 3 (final design round; branch worktree-wf_d864cd42-ccc-2, CI branches ci/webkit-sim-failfast-r3f, -r3n)

Read first: lean/Fw/Measure/SimBound.lean, packages/measure-webkit/src/guard.mjs, research/notes/2026/10-20-macos-pool-v2.md (rows 3, 4).
Code head 5d557d07: Lean check.sh green, measure-webkit 108/108, ci-paths 47/47, land-inputs 55/55, 0 skipped, no skip in the diff.

Seen table (`SimBound.Seen`, the one home of measured maxima; the workflow comments and the note cite it)
| what | value | run |
|---|---|---|
| longest green silence | 491 s | 39343967737 (others 318 s 39357736128, 266 s 39447981526, 259 s 39435518921) |
| slowest boot step / setup | 305 s / 343 s | 39444758495 |
`stallMs` = 720000 (main's 8 x 90000; `stall_covers_seen`: 10*stallMs >= 13*491000). `setupMin` = 8 (`setup_covers_seen`: 8*600 >= 13*343).
`jobMin` = 8 + 35 per session + 10 (53 for one session). Note row 4 is withdrawn (491 s green silence > 6 min/1.3; saves 0).

Lean (all proved, no sorry): `afterRelaunch ok` (false -> giveUp, true -> proceed) is used by `monitor ok ...`; `repairMs` = stop 2 s + lsof 5 s + proxy 35 s = 42 s;
`deadEndMs` = 2*detect 85 + 2*repair 42 + relaunch 320 + exit 40 = 614 s; `detect_le_stall` stays the backstop.
Two paths: `failed_relaunch_ends` (monitor = replicate n proceed ++ [relaunch, giveUp], n < 2, time + exit <= 487 s <= deadEndMs; CI path) and
`dead_run_ends` (dead-again after a good relaunch, `timeMs` + exit <= deadEndMs; unit tests and goldens only, limit (a)).
TS stand-in `inspectorAfterRelaunch` (inspector.mjs) checked against `measure.inspector` goldens (new optional `relaunchOk`); guard.mjs calls it; relaunch behaviour unchanged. Also: probeInspector uses the listPageTabs filter (tested).
CI (webkit-sim, original, 1 session), runs used: 3 (2 planned + 1 rerun, see Open)
- Fault kill-proxy run 39459660693 attempt 2 (head 5187d2f8): first kill 17:14:01Z, probe failed 17:14:02Z, 2nd failed + "relaunching" 17:14:07Z,
  "giving up: relaunching Safari failed: lsof: ETIMEDOUT; exit code 4" 17:14:43Z, evidence line `cli: exit 4` 17:15:04Z = 63 s after the first kill (bound 614 s; failed-relaunch path).
- Normal run 39459689946 (head 06f7419a, same code): green, `cli: exit 0`, no probe failure or relaunch line. Classes 58 deterministic / 14 stable / 32 quarantined
  (39447981526: 56 / 10 / 38; baseline 39102911639: 58 deterministic); the quarantined census rows vary between runs (limit (f)).
Open
- The first attempt of 39459660693 died at start with `error: lsof: ETIMEDOUT`, `cli: exit 1` (16:54:25Z, before the fault armed; source not determined: waitSocket, 5 s cap on this branch until the lead fix, or startProxy, 30 s as on main). I reran the failed job once (3rd run, over limit (i)).
  lsof is slow on these runners (also the 5 s lsof in the relaunch). Lead fix: waitSocket treats an lsof error as "no socket yet" until its deadline and gives lsof the time left. Follow-up: the relaunch lsof bound.
- Follow-ups: #5 relaunch holds a closed client, #6 end-of-run probe can relaunch, sim-seen-table, cause of inspector deaths.
- Main moved on after the merge; the lead merges it again at land. No write outside the task's files; work-graph.json untouched.
Convention: goldens: `lake build Fw.Measure.Golden Fw.Measure.Wire`, then `lake env lean --run scripts/MeasureGolden.lean` in lean/; rebuild fwcore before node tests.
