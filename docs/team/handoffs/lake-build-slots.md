# Handoff: lake-build-slots
**State:** branch `worktree-wf_6c3ae4fd-86e-2`, round 3 (final design round); wrapper code 0109e9a, later commits change
only a test probe, docs and one docstring. At the final commit: check.sh green, runner tests, ci-paths 41/41, lake-slot 12/12.
**What exists:** `lean/Fw/Sched/LakeSlot.lean` (pools `[full, cap 4]`, `pick`, `bound n = n + 4` = 12, `held_threads_le`,
generates `golden/sched/lake-slot.gen.sh`); `scripts/lake-slot-lib.sh` only defines `lake_slot <root> <cmd>` (fd 9 lock, exec),
`scripts/lake-slot.sh` sources it and always runs the CLI; `fwcore-build.sh` and the land axiom lint source the lib. CI:
lean.yml runs `scripts/lake-slot.test.mjs` on Linux (flock); apps/runner `ci-triggers.test.ts` runs it on a land.
**Bench** (local debug, spans `lake-slot/bench` in main's `.fw-console/timings.jsonl`, pairs alternate order, delta =
slot - plain, paired median; d3d2598 read load once per session, 0109e9a once per pair; A/A rows are the noise floor):

| commit | group | n | plain ms | slot ms | delta ms | slot slower | load | session s |
|---|---|---|---|---|---|---|---|---|
| d3d2598 | startup true (CLI) | 60 | 12 | 21.5 | +9.5 | 58/60 | 11.0-18.6 | 2+1 |
| d3d2598 | noop lake (CLI) | 40 | 190 | 198 | +8 | 32/40 | 13.9-18.6 | 10+8 |
| d3d2598 | noop lint form | 40 | 188 | 192.5 | +4.5 | 29/40 | 13.9-18.6 | 9+8 |
| d3d2598 | noop fwcore-build | 40 | 356 | 404.5 | +11.5 | 31/40 | 13.9-18.6 | 27+12 |
| d3d2598 | noop lake A/A | 20 | 262 | 254 | +3 | 12/20 | 13.9-18.6 | 9+4 |
| d3d2598 | noop fwcore-build same-root | 40 | 296 | 297 | 0 | 18/40 | 7.3 | 24 |
| d3d2598 | noop fwcore-build A/A | 20 | 293.5 | 293 | -1 | 7/20 | 7.3 | 12 |
| d3d2598 | clean small | 10 | 7262 | 7482 | +81.5 | 5/10 | 15.4 | 166 |
| d3d2598 | clean Admit.lean | 5 | 144642 | 147856 | +2102 | 4/5 | 12.8 | 1597 |
| 0109e9a | startup true (CLI) | 30 | 9 | 18 | +9 | 30/30 | 5.3-6.2 | 3 |
| 0109e9a | noop lint form | 20 | 185 | 188.5 | +4.5 | 17/20 | 6.2-8.0 | 8 |
| 0109e9a | noop fwcore-build | 20 | 430 | 429 | -9.5 | 9/20 | 8.0-15.7 | 22 |
| 0109e9a | noop lake A/A | 20 | 185 | 186 | -1 | 9/20 | 14.8-15.2 | 8 |

Fixed cost per no-op build +4.5 to +11.5 ms; clean builds as measured, no clean A/A. Overlap at 0109e9a (3 scratch Lake
projects x 10 Init-only modules, `ps` every 100 ms, load 18.6-24): plain peak 20 lean, 7.3 GB summed RSS; slot peak 11, 4.3 GB.
**Open:** lake serve, ad-hoc lake calls and check.sh stage 2 run without a slot (follow-up check-stage2-bound); lean threads
unbounded; a descendant that outlives lake keeps fd 9; hw = 8. **Read first:** `LakeSlot.lean`, `lake-slot-lib.sh`, its test.
