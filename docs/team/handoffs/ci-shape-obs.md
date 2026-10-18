# ci-shape-obs handoff

State: branch worktree-wf_bd9d7470-69f-3; work in 208f86b, the main merge df435fd, then a docstring and handoff commit
on top (see `git log -3`). It is not landed.

Read first:
- the design note `research/notes/2026/10-18-ci-shape-obs.md` (records, classes, thresholds, replay, interface to
  gate-shard-balance);
- `lean/Fw/Obs/CiShape.lean`.

What exists:
- Lean `Fw.Obs.CiShape`: four drift classes, imbalance, growth, nearTimeout and queue, deduplicated per
  (workflow, class). 20 theorems, standard axioms only.
- `obs.ciShape` is dispatched from `Fw.Wire.Ops.handle`. Its goldens are in
  `packages/contracts/golden/obs/obs.ciShape.jsonl` (16 cases, from `lean/Fw/Ops/Golden.lean`; regenerate with
  `lake env lean --run scripts/OpsGolden.lean`).
- Glue: `apps/runner/src/ci-shape.ts` (collector, `shapeFor`, `shapeAlerts`).
  - `fw ci wait` collects the runs it saw finish.
  - `fw watch` collects from the poller's `runs-status.json` and the snapshot.
  - It writes the `ciShape` reply on the health line and raises `ci.shape` alerts.
- Console: console-api passes `ciShape` through; the Health tab has a "CI shape" card.
- The ledger is `.fw-console/ci-shape.jsonl` in the main checkout. Set FW_CI_SHAPE_FILE to point elsewhere; under
  vitest it is off.

Conventions:
- Seconds are Nat, and ratios are compared cross-multiplied.
- One charged `gh run view` per finished, non-cancelled run (gh-budget cost 2), at most 4 per pass.
- Tests use recorded fixtures in `apps/runner/test/fixtures/ci-shape/`.

Open items:
- `fwcore --ops` does not list `obs.ciShape` yet. `Fw.Wire.Ops.obsOps` must be appended in `lean/Fw/Wire.lean`; that
  file was outside my write scope, and the OpsWire mutant guard pins `Fw.Wire.Ops.ops`.
- The docstrings were self-reviewed against the 6-point checklist; no `checker` was spawned (no spawn tool).
- After landing, the lead should seed the ledger from the backfill and watch one live `fw watch` pass.
- gate-shard-balance should read the ledger and reuse `imbalanced` as its acceptance test (see the note).
