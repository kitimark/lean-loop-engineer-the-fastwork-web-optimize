# incident-lint handoff

State: committed on branch worktree-agent-a888b70ebfa7a622d (see `git log -1`); not landed.

What exists
- `lean/Fw/Plan/Incident.lean`: `holds`/`codes` per incident (13 codes, 11 errors, 2 warnings), `status` (fixed/fixing/open,
  derived only), `lintAll`, `okAll`. Theorems: `mem_codes`, `status_fixed_iff`, `status_fixing_iff`,
  `fixed_no_missingFixTask`, `holds_addEvidence`, `errors_addEvidence`, `holds_mono_facts`, `lintAll_perm`, `okAll_perm`.
- Wire op `plan.incidentLint` in `lean/Fw/Wire/Plan.lean` (`ops`, `handle`). Dispatch: `Fw.Wire.Serve.serveLine` (Serve.lean,
  4 lines) because Wire/Plan imports Fw.Wire, so `Fw.Wire.handleCore` cannot call it; `fwcore --ops` lists it (Main.lean).
- CLI `pnpm fw incidents lint [file]` in `apps/runner/src/incidents.ts`; fw.ts: dispatch line (dynamic import), usage text,
  and `incidents` added to the groups that need no console-api (board optional; fallback = work-graph.json states).
- Golden `packages/contracts/golden/plan/incident-lint.jsonl` (27 cases) is written and checked by
  `apps/runner/test/incidents.test.ts` against the fwcore binary (`FW_WRITE_INCIDENT_GOLDEN=1` regenerates).
- Docs: `docs/team/incidents/README.md`.

Conventions
- Facts (commits on main, existing files, task rows) are collected in TS; every decision is Lean. Evidence ref forms reuse
  `Fw.Plan.Lint.isCommit` / `isRun`.
- "Adding evidence never adds an error" is proved as: new findings come only from the added items
  (`holds_addEvidence`); with error-free items, no new error (`errors_addEvidence`).

Open items
- The golden is not checked by `lake test` (FwTestMain/Ops.Golden were out of scope); the runner vitest checks it.
- Ledger fix: inc-unlanded-handback cited `docs/team/handoffs/integrate-ports.md`, which exists only on the unlanded
  branch ci/integrate-ports; the file evidence was removed and noted in the ci evidence note.
- Not yet a land check: wire `fw incidents lint` into land checks / pre-commit if the lead wants it enforced.

Read first: the module header of `lean/Fw/Plan/Incident.lean`, then `docs/team/incidents/README.md`.
