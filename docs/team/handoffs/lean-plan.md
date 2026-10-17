# lean-plan handoff

**State:** the work graph is specified, proved and served by fwcore. Commit: see `git log -1 -- lean/Fw/Plan` on branch
`worktree-wf_c2b8a932-977-1`. `lake build` is green with 0 warnings, `lake test` passes all suites (plan golden: 10 cases plus
the work graph), and the mathview lint shows 0 failing and 84 warnings (the baseline).

**Read first:**
- `lean/Fw/Plan/Graph.lean`: `Dep`/`Acyclic`, the Kahn check (`acyclicB_iff`), `criticalPath` (`criticalPath_longest`) and the glob overlap (`globOv_sound`).
- `lean/Fw/Plan/Core.lean`: `Cmd`, `check`, `exec`, `step`, `tstate`/`blockers`, `Inv` (`run_inv`), `step_isDone`, `groups` (`groups_pairwise`) and `view`.
- `lean/Fw/Wire/Plan.lean`: the JSON wire form.
- `lean/Fw/Plan/Golden.lean`: the goldens in `packages/contracts/golden/plan/`.

**Conventions:**
- Plan commands use the normal event envelope (`key`, `ts`, `actor`, `type`).
- Authority is in `Console.mayList`:
  - `task.define`, `task.drop`, `milestone.define`: lead, user, script.
  - `task.claim`: hook, script, lead.
  - `task.done`: git, lead, user.
- State is derived and never stored:
  - done: evidence is present.
  - running: claimed and not done.
  - ready: all deps are done.
  - blocked: anything else.
  - `blockers` is always the list of undone deps, so a running task can still show blockers.
- `task.define` is an upsert: an existing row keeps its claim agent and its evidence.
- The board plan is the `plan` field of the stateful `console.query` board only.
- Regenerate the goldens with `cd lean && lake test -- --write-plan-golden`. `lake env lean --run` fails in worktrees whose oleans come from the artifact cache.

**Open items:**
- The stateless ops `console.apply`, `console.board` and `Wire.stateJson` (Wire.lean) do not carry the plan. I made zero Wire.lean edits on purpose.
- Edits outside the declared writes: `Fw/Serve.lean` (Srv.plan, Resp.board plan), `FwTestMain.lean` and `FwTest/Serve.lean` (the board-golden query compare now expects `plan`).
- Extra refusals beyond the contract: dropping a done task ("task is done"), and the define limits on title, deps, writes and devices.
- `work-graph.jsonl` is a snapshot of `docs/team/work-graph.json` at generation time. It is checked by replay, not against the live JSON, so regenerate it after graph edits.
- Worktree build note: wt-prep traces came without oleans for 34 modules, which breaks mathview and `lake env lean --run`. A one-off local `lake build` with the artifact cache off fixed it; the lakefile is unchanged.
