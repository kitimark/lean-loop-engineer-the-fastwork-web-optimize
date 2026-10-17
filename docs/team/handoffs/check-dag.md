# check-dag handoff (branch worktree-agent-a3cd2e04202b1f052)

State: lean/scripts/check.sh is a DAG; apps/runner/src/land.ts runChecks runs checks concurrently. Runner tests green (370).
- check.sh: serial grep gates, import check, `lake build && lake build fwtest`; then in parallel (background jobs, output in a
  temp dir, built binaries called directly): mathview lint, fwtest, golden wire replay, 5 breakgen checks. Spans per stage plus
  "parallel group". Every failing stage is listed; exit 1 if any. A failed build ends the run (the parallel stages need it).
- land.ts: `checkDeps(list)` (exported) = everything waits for `pnpm install`; FWCORE_USERS tests wait for `sh lean/scripts/check.sh`
  (its lake build writes the binary). Pool = `o.concurrency ?? availableParallelism()`. All verdicts collected; refusal lists every
  failure ("check FAILED: ..." blocks). Selection unchanged (checksFor).
- Soundness: Lean Fw.Console.LandSpeed.verdict_perm (verdict = conjunction of check verdicts, independent of order and completion);
  cited in comments of both files.
- Tests: apps/runner/test/land-post.test.ts (one failing reported alone; two both; overlap in time), land-parallel.test.ts (checkDeps).
- MEASURED local (one run, warm .lake): check.sh 26.9 s sum of spans (26.2 s wall) -> 5.8 s wall. Critical path = serial 0.8 s +
  longest breakgen check ~4.9 s (each breakgen run costs ~4.8 s itself; `lake exe` overhead was small). Next: one breakgen process
  for all five checks would cut the path to ~1 s.
- Open: mathview-cached.sh uses `lake exe` on a cache miss (Lake lock, fine because nothing else holds it then).
