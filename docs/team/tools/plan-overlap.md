# fw plan overlap

Run before every spawn: `pnpm fw plan overlap <task> [--running a,b] [--override "<reason>"]`.

- Decision: Lean `Fw.Plan.Overlap` via the fwcore op `plan.overlap`. Two write globs overlap when some non-empty path is
  covered by both (`Fw.Ops.PathCheck.matchesPath`: a glob covers the path and everything below it). Proved sound and
  complete (`globsOverlap_sound`, `globsOverlap_complete`), so no overlap is missed and none is invented. `!` excludes are
  not read, so a pair an exclude separates is still reported.
- Running tasks: the board's tasks with a live agent and no landed evidence (the `running` state of `Fw.Plan.Core.tstate`),
  or the ids in `--running`. Without `<task>` every pair of running tasks is checked.
- Verdict and exit code: `clear` 0; `refused` 1 (finish or park one task, split the writes, or override); `overridden` 0
  and recorded; `unknown` 2 (an id is not in `docs/team/work-graph.json`; never overridden).
- Override: a non-blank `--override` reason is posted to the event log as a `step.post` (audience lead) closed at once by
  `step.done` with the reason as note; if the console-api does not accept it the exit code is 2 and the task is not started.
- Advisory: the Workflow tool has no hook, so the lead runs this itself. Golden: `packages/contracts/golden/plan/overlap.jsonl`.
