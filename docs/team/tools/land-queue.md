# fw land --queue: lands in first-in-first-out order

`pnpm fw land --queue <branch> --task <id> [--allow <glob>]... [--no-run]` appends one `enq` line to `.fw-console/land-queue.jsonl` (a task already pending is not added twice), then becomes the single runner if no live runner holds `.fw-console/land-queue.runner`, and lands the pending entries head first. `--no-run` only enqueues. `pnpm fw land --queue-status` prints one `VERDICT queued <task>` per pending entry and `VERDICT <kind> <task>` for the last result of each finished one. Verdict kinds and exit codes: `land.md`.

- The log is the only state: `enq` and `res` lines; the pending list is their fold (Lean `Fw.Console.LandQueue`: `enq_idem`, `enq_appends`, `res_head`, `pending_nodup`).
- The runner retries an entry only for `busy` and `dirty`, at most 5 attempts (`retryAfter_iff`, `retryAfter_bounded`, `retryAfter_final`); it reads the kind from the land's result, never from its text.
- The runner lock holds (pid, start time of `ps -o lstart= -p <pid>`); a holder is live only when the start time now at that pid is the recorded one (`runnerLive_iff`). No process is found by a command-line pattern.
- `fw watch` / `fw next` raise no `agent.unlanded` for a branch that is a pending entry (`Fw.Obs.Next.no_unlanded_while_queued`, fact `landQueued`).
- The exit code of `--queue` is the kind of this task's result, or 0 with `VERDICT queued` when another runner (or `--no-run`) will land it.

Queue overhead about 10 ms per land (3 tiny fixture branches, real land, no CI, in-process; a local debug run, not a result).
TS stand-in `apps/runner/src/land-queue.ts`, checked against `packages/contracts/golden/console/land-queue.jsonl`.
