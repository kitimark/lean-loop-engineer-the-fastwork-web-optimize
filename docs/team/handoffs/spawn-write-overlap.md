# spawn-write-overlap handoff

State: committed on branch worktree-wf_06230cac-6e8-2 (see `git log -3`); not landed. `sh lean/scripts/check.sh` green;
`pnpm --filter ./apps/runner test` 1653 pass (tsc included); `node --test scripts/ci-paths.test.mjs` 49 pass.

What exists
- `lean/Fw/Plan/Overlap.lean`: `segInter`/`globInter` (glob intersection over the `Fw.Ops.PathCheck` syntax), `globsOverlap`,
  `conflictsOf`, `conflicts`, `verdict` (clear/refused/overridden/unknown). Proved: `globInter_iff` (sound + complete against
  `globMatch`), `matchesPath_iff`, `globsOverlap_sound/complete/comm`, one theorem per verdict branch, `overlap_not_clear`.
- Op `plan.overlap` in `lean/Fw/Wire/Plan.lean` (+ import in `lean/Fw.lean`). Golden `packages/contracts/golden/plan/overlap.jsonl`
  (17 cases) checked by `apps/runner/test/plan-overlap.test.ts` against the fwcore binary (`FW_WRITE_OVERLAP_GOLDEN=1` regenerates).
- CLI `pnpm fw plan overlap [<task>] [--running a,b] [--override "<reason>"]` (`apps/runner/src/plan-overlap.ts`, wired in fw.ts).
  Running = board tasks with agent and no evidence (Fw.Plan.Core.lean:329 `tstate` running; board read as in incidents.ts boardTasks).
  Override is recorded as `step.post` (audience lead) + `step.done` (note = reason); unrecorded override exits 2.
- Glob semantics reused from `lean/Fw/Ops/PathCheck.lean:22-47`; TS stand-in `inScope` (land.ts:150-165) is not used here.
- Timing: `fw plan overlap` 0.49 s wall; `fw` writes its span to timings.jsonl like every command.

Writes outside the task's graph writes (report): `lean/Fw/Wire/Plan.lean`, `lean/Fw.lean`, `apps/runner/src/fw.ts`.

Open items
- Advisory only: no hook in the Workflow tool; the lead must run it before a spawn. Excludes (`!`) are ignored (conservative).
- Running tasks are read from the board; a task claimed but not yet reflected in the board is missed (pass `--running`).
- Overlap of the real graph is broader than the pair named: golden/parts and research/findings/ledger.json also collide.
- TS stand-in: runningOf (running set) -> Lean; output should name the running set it checked (an empty set prints CLEAR like a real clear); count handed-back-unlanded tasks as running; test that an exclude does not separate a pair; exercise the override record on the real event log; Wire/Plan.lean and Fw.lean edits are outside the graph writes (lead approves at land).

Read first: `docs/team/tools/plan-overlap.md`, then the module header of `lean/Fw/Plan/Overlap.lean`.
