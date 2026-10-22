branch: worktree-wf_a3ba2392-7af-1
worktree: .claude/worktrees/wf_a3ba2392-7af-1
last commit: see `git log -1` (work commit 77d7d848, then main merged and this handoff)
CI runs: none (no CI push needed; the unit is runner code and tests)

State: task run-span-split built, runner test (87 files, 2422 tests, tsc incl.), scripts/ci-paths and slot-self tests green.

What changed
- apps/runner/src/fw-groups.ts: `SUBCOMMANDS` table + `spanStep(group, rest)`; fw-main.ts names its span with it (old hand `SUBS` set gone).
- apps/runner/test/span-names.test.ts: reads fw-main.ts, fails when a dispatch branch reads `rest[0]` for a group missing from the table, or a `group === g && rest[0] === s` pair is missing; also covers slot names and run phases.
- apps/runner/src/run-phases.ts + run.ts runCli: `run dispatch`, `run wait` (runId), `run file`, `run dry`; no `run` span.
- apps/runner/src/slot-span.ts (no imports): `slot run <kind>`, `slot acquire <kind>`, `slot admit`, `slot status` ...; used by fw.ts and scripts/slot-self.mjs.
- apps/runner/src/land.ts: `stepPrefix` "dry " for a dry land (`dry total`, `dry merge`, ...); test in land-dry.test.ts. fw span for a dry land is `land dry`.
- docs/team/tools/timings.md: new section.
- card.ts: DEFAULT_ACTOR exported (the card subcommand list).

Verified: Fw.Obs.Timing keys on (tool, step, host, kind) as free strings, so no Lean change; the land ceiling (`fw land`/`total`) now judges real lands only.
Open / follow-ups
- SUBCOMMANDS is a hand table checked against fw-main.ts by a test, not parsed from a CLI table object (the dispatch is an if-chain).
- Old samples keep old names (`run`, `slot`, `land`, `total`); no log rewrite. Dry lands get no ceiling.
- Writes outside the graph's list: card.ts, fw-groups.ts, run-phases.ts, slot-span.ts, scripts/slot-self.mjs, tests, this handoff.
Read first: apps/runner/src/fw-groups.ts, run-phases.ts.
