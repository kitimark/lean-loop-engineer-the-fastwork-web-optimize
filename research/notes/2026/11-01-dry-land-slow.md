# dry-land-slow: closed as a finding (premise refuted)

Task dry-land-slow (graph r615) asked why `fw land --dry` "got slower" (timing.slow alerts: 34.6 s, 38.1 s, 33.3 s against a
p50 of 21.7 s, budget 30 s) and how to cut it back. Two build-review rounds were refused; a Fable investigation
(fable-refusals, run wf_590291a8-320) and its adversarial check found that the premise does not hold. Nothing grew. No code
from the task branch (worktree-wf_779ff154-e9a-1 at 3f8a055b2) lands; the branch stays as the base of follow-up B.

Source of every MEASURED line: `.fw-console/timings.jsonl` and `.fw-console/locks.jsonl` (local only, not committed); each
line names its row key (commit, startMs) or row numbers.

## Finding

1. MEASURED: a dry land takes the sum of its selected checks along the dependency chain. In all three alert samples the
   critical path is claims ~1.2 s + reads test 9.7-10.0 s + lake lint 6.7-8.9 s (built 0) + fwcore-build 1.0 s +
   overflow-widths 11.9-12.9 s. Rows: 0180811 startMs 1793431500999 34.6 s; 0058ef3 1793436388545 38.1 s; 001d247
   1793478536258 33.3 s.
2. MEASURED: nothing on that critical path grew since 10-25. Two spans off the path grew (daily medians): the compose test
   3.2 s (10-22) to 7.1 s (10-31, 11-01) and the workflow lint 1.9 to 2.7 s. In every alert sample compose ends before
   overflow-widths (001d247: compose ends at 28.10 s, overflow-widths at 33.01 s).
3. MEASURED: this check-set shape first existed on 10-24, when a workflow change started selecting overflow-widths
   (94f974b89). Its daily p50 has been 30.0-35.2 s every day from 10-25 to 10-31. The "p50 21.7 s" baseline mixes in runs
   that hit the lake pass cache (a10d2e549, 10-24), which skip the lake lint.
4. MEASURED: host load is not the cause. Same commit 37a77f8: 32.6 s with the lake lint at load 2.78, 27.7 s without it
   (cache hit) at load 3.98.
5. MEASURED: cold-lake runs (built > 0) took 29.0-42.3 s (10-30 to 11-01, built 6-24).
6. MEASURED: running the three dry phases in one wave (the task branch) cut a warm set from 25.2/26.0 s to 15.8/15.8 s,
   but it let the lake lint and `scripts/fwcore-build.sh` run `lake build` at the same time in one land-wt `lean/.lake`.
   There are two Lake slots, not one (`LAKE_SLOT_POOLS='full 4'`, lean/Fw/Sched/LakeSlot.lean:276; scripts/lake-slot-lib.sh
   `_ls_take`), and Lake takes no build lock (CONFIRMED, Lake/Util/Lock.lean:17-20 at lean4 eb6cafb, v4.35.0). Both slots
   were taken within 82-88 ms in locks rows 20291-20292, 20295-20296 and 20307-20308.
7. The branch's only lake-miss run failed: commit 09ab4c0, startMs 1793485018826, built 2, exit 1; the lake lint and
   fwcore-build both ran from 0.91 s to 16.55 s. INFERRED cause: a race on hard-linked .olean files (enableArtifactCache,
   lean/lakefile.toml:8-14). Not proven: the error text was overwritten by the passing rerun.

## Lessons

- A CONFIRMED tag needs its file:line read in that round. The branch note tagged "one build at a time" CONFIRMED from a
  comment in lake-slot-lib.sh; the slot count is two. Same class as incident inc-number-from-memory.
- The lead's task prompt offered two causes (growth, host load) and neither was true. The prompt should have asked for
  attribution only and left the cause open.
- A run of new code that fails once and passes on retry is evidence, not noise: the one failed lake-miss run was the race.

## Follow-ups (graph r616)

- dry-land-timing-key: the timing key of the dry steps carries the identity of the selected check set, so the relative
  slow rule (lean/Fw/Obs/Timing.lean:1173-1177) compares like with like. Timing only; speed and land semantics unchanged.
- dry-land-waves: the parallel run from the task branch with a Lean dependency rule (`Fw.Ops.LandDry.deps`: fwcore-build
  after the lake lint, fwcore users after both; theorem `lake_serial`), measured on 001d247's exact check set with warm and
  cold runs. INFERRED warm critical path after the edges: about 23 s.
