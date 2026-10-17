# lean-wire-sched handoff

**State:** E8 minus `ops.gate` (Gate is not built yet) is done on branch `worktree-wf_eaf1cd1e-ed1-2`
(commit: see `git log -- lean/Fw/Wire/Sched.lean`). `lean/scripts/check.sh` is green. Only standard axioms are used.
No edits to `Fw/Sched/*.lean`.

**Files:**
- `lean/Fw/Wire/Sched.lean` (namespace `Fw.Wire.Sched`): codecs and the ops `ops.admit` and `metrics.{merge, busy,
  speedup, serialShare, stretch, cp, benchVerdict}`, registered in `Fw/Wire.lean` (`ops`, `handleCore`).
- `lean/Fw/Wire/SchedGolden.lean` and `lean/scripts/SchedGolden.lean`: write or `--check` the goldens
  `packages/contracts/golden/ops/{admit,metrics}.jsonl`; `lake test` checks them (`FwTestMain.lean`).
- `lean/golden/wire-{requests,replies}.txt`: +4 lines (`s-1`..`s-4`).
- `check-partial.sh` also scans the two new files.

**Behaviour:**
- `ops.admit` takes `budget`, `state`? (defaults to empty), `event` `{type: admit|finish|enqueue|tick}` and `probe`?.
- It replies with the state after `event` (step, then `admitAll`), `admitted`, a decision for every queued item,
  `probes` (each judged as if enqueued now), and `inv`/`invAfter` (`invB` = `Inv`).
- The first 18 admit cases are one chained scenario: each request's state is the previous reply's state.

**Theorems:**
- Round trips: `stateOf_stateJson`, `itemOf_itemJson`, `vecOf_vecJson`, `cmdOf_cmdJson`, `ivOf_ivJson`.
- `invB_iff`, `invB_event`, `inv_steps`, `event_queued_wait`, `opAdmit_state`.

**Conventions:**
- Fractions are `{num, den}` strings (as `Fw.Wire.ratToJson`, duplicated locally because of the import cycle).
- Intervals and edges are `[a, b]` pairs.
- `Fw.Wire.*` is skipped by the math-view lint, but every theorem docstring has `$$` math anyway.

**Open items:**
- `ops.gate` waits for `Fw.Ops.Gate`. Add it to `Fw.Wire.Sched.handle` and a `gate.jsonl` golden.
- With `base = 0`, items are aged at once, so the `comp` budget clause blocks everything behind an aged over-budget
  item (see the "aged o" case). Callers should send a real `base`.
- There are no TS consumers yet (spawn-guard, `fw plan`, `fw job`).

**Read first:** the module doc of `Fw/Wire/Sched.lean`, then `admit.jsonl`.
