# obs-next-lean handoff

**State.** Worktree branch of obs-next-lean (the commit that adds this file). `lean/Fw/Obs/Next.lean` decides `next : Params → Nat → AgentFacts → List Action`.
The wire op `obs.next` and the golden generator `Fw.Wire.Obs.NextGolden` are in `lean/Fw/Wire/Obs.lean`. 45 golden cases are in `packages/contracts/golden/obs/next.jsonl` (lead cases 1–7 plus edges). `sh lean/scripts/check.sh` is green.

**Read first.** The module doc of `Next.lean` (rules), then the `obs.next` shapes in the `Wire/Obs.lean` module doc.

**Facts for obs-next-glue (TS) and how to observe each.**
- `id`, `task`: the agent's name and task id (spawn record / board).
- `state`: the `obs.health` reply for the same snapshot.
- `handbackAt`: transcript, time of the `SubagentHandback` call (absent: none seen).
- `session`: the pid of the agent's Claude session (ps).
- `ctxTokens`: transcript, last usage (input + cache read + cache write).
- `branch.name`, `ahead`: `git rev-list --count main..<branch>`.
- `branch.landed`: `git merge-base --is-ancestor <branch> main`.
- `branch.queued`: whether the branch is on the integrator's list.
- `worktree.lockPid`: the pid in the `git worktree list --porcelain` lock reason.
- `worktree.lockAlive`: `kill -0 <pid>`.
- `children[]`: from ps (`ps -o pid,ppid,lstart,command`).
  - `pid`; `chain` = the ppid, then its ppid, … up to 1 (must reach `session`); `startedAt` = lstart in ms.
  - `kind`:
    - sleepLoop: `until …; do sleep` / `while … sleep`;
    - ciWait run timeoutMin: `waitrun.sh <run>` and its timeout;
    - build: lake/node/pnpm build or test;
    - other: anything else.
  - `watchedAt`: the mtime (ms) of the file the loop greps (stat).
  - `producerExited`: that file's last line is `[exited with code N]`.
- `ci`: the latest run of `ci/<task>` (`gh run list --branch ci/<task> -L 1`): id plus the CiRun fields.
- `board`: the board row whose id equals the agent's name: `{id, done, agent?}` (absent: no such task).

**Conventions.** Params: Health params plus `loopCapMin` 30 and `fileStaleMin` 10 (justifications in the `Params` docstring). Every number is a natural number in ms, and a `…Min` field is in minutes. Thresholds are strict (`>`), and an age is `now ∸ t`.

**Open items (lead).**
- (a) No `lake test` hook yet checks `next.jsonl` for staleness, because `FwTestMain.lean` / `scripts/` are not my files. Add `Fw.Wire.Obs.NextGolden.run "." false` next to the health golden check.
- (b) The regenerate script is only in my scratchpad: a two-line `main` calling `NextGolden.run "." true`.
