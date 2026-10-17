# lean-ops handoff

**State:** M0 `Fw/Ops` done on branch `worktree-agent-ae9a708540ef53fad` (commit: see `git log -- lean/Fw/Ops`).
`lean/scripts/check.sh` green, `lake exe mathview --lint` 0 failing, standard axioms only, no sorry.

**Modules** (`lean/Fw/Ops/`):
- `SpawnGuard`: `decide : Input → allow | needsApproval | deny reason`. Proved `accepted_within` (all caps hold
  after the spawn), `accepted_rate`, `accepted_names_nodup`, `trap_worktree_role_as_teammate` + `trap_exact`,
  `teammate_with_isolation_denied`, `ask_never_allow`, `ask_needs_approval`, `accepted_nested_read_only`.
- `PathCheck`: gitignore-like globs (`**`, `*` in a segment, directory prefix, `!` excludes, `..` never in scope).
  `mem_violations` (sound + complete), `inScope_iff`, `excl_wins`, glob laws.
- `Usage`: per-field max join keyed by `message.id`, sorted table; `merge_comm/assoc/idem`, `ingest_perm`,
  `ingest_append`, `ingest_dup`, `get_ingest`; `lastWins` kept only as the #guard counterexample.
- `Meter`: port of `docs/team/tools/agent-idle.py` (seconds): `ctxBig`, `idleExpiring` (idle + 60 > ttl),
  `coldWake` (wake gap > ttl), verdicts; `holds_mono`, `verdict_mono`, `once_per_window` (needs non-decreasing times).
- `Wire` (`Fw.Wire.Ops`, lint-exempt glue): ops `ops.spawn`, `ops.pathCheck`, `ops.usage`, `ops.meter`, `ops.hook`;
  JSON shapes in the module doc table. `Golden`: cases → `packages/contracts/golden/ops/*.jsonl`.

**Conventions:** same as `Fw/Measure/Wire` (own total decoders, no `!` accessors). Regenerate goldens with
`cd lean && lake env lean --run scripts/OpsGolden.lean`; `lake test` checks them (2 lines added in `FwTestMain.lean`).
Registration in `Fw/Wire.lean`: 1 import, `++ Fw.Wire.Ops.ops`, one `match Fw.Wire.Ops.handle` fallthrough.

**Open items (for the lead):**
- PLAN conflict: §8.3 denies unnamed calls, §8.1 says a named call without isolation becomes a teammate, so a
  read-only subagent (reviewer, Explore) cannot be spawned from the lead under both. `caps.unnamedReadOnly`
  (default false = PLAN literal) lets unnamed read-only subagents through; the lead/plan-editor should decide.
- `effKind` (depth ≥ 1 named call without isolation = subagent) is INFERRED from "no nested teams"; SPK-p to confirm.
- `check-partial.sh` does not list `Fw/Ops/Wire.lean`, `Fw/Ops/Golden.lean`, `scripts/OpsGolden.lean` (they pass
  its regex today); add them when someone owns that script.
- No mutants (V-r) yet for Fw/Ops.

**Read first:** `lean/Fw/Ops/Wire.lean` module doc (op table), then `SpawnGuard.check` and `Meter.step`.
