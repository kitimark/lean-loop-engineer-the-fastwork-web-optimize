# gate-no-skip handoff

**State:** branch worktree-wf_05b51fbd-31a-2. Work commit 612e9678 (measured on ci/gate-no-skip); docs and main merge on top.
Note: research/notes/2026/10-18-gate-no-skip.md.

**What changed**
- `lean/Fw/Gate/Exit.lean`: exemptions list rows and ids (no `none` wildcard; WebKit ones list `gateRows` × `blockIds`);
  `gateUniverse` = rows × cols × ids (3528 keys); new verdict `refused` via `engineVerdictU`; `runExit` is 1 when narrowed.
  Theorems: `exemptions_enumerated`, `exemptions_in_universe`, `excused_in_universe`, `universe_identity(_run)`,
  `narrowed_never_zero`, `runExit_zero_iff`, `exit_zero_iff_all_cells` (restated with U, N), `fractional_chromium_lean_na`.
- `exit.jsonl`: 87 lines with a `universe` line; engine cases carry `universe`, exit cases carry `narrowed`.
- `cli.mjs`: reads the universe from `exit.jsonl`; `narrowed` = the `--parts` flag (`engineOfSummary(name, e, narrowed, reg)`);
  prints `gate readings <engine>: total, pass, excused, bad; universe ...; table sha256`; writes `readings-<engine>.json`;
  exits through `runExit`.

**Verified**
- `sh lean/scripts/check.sh` green; `node --test` in packages/gate-breakpoints 134/134; axioms standard only.
- CI push run 39130848323 and dispatch run 39130859625 give identical tables: chromium 3528/3521/7/0 (pass),
  webkit 3528/3366/147/15 (fail, red as expected).
- Mutant run 39130919551 (ci/gate-no-skip-mutant, 3602cf62, never landed): chromium bad 1, verdict incomplete, exit 1.

**Open items**
- touch-1024 breakgen vectors (outside scope: BreakpointGen.lean, spec.mjs).
- The breakpoint-gate workflow should pass `--parts` to `summary`; today a dispatched narrowed run is refused by the
  universe check, which still exits 1.
- No `checker` was spawned (this agent had no agent-spawn tool); docstrings were self-checked against the 6-item list.

**Read first:** Exit.lean sections "Exemptions" and "One engine of a run"; test/exit.test.mjs "full universe".
