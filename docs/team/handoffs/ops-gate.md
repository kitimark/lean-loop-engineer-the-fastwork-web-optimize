# ops-gate handoff

**State:** `ops.gate` (E8 remainder, parallel plan §3.3) is on fwcore; commit on branch
`worktree-agent-a8ca5abd7d786b30f` (see `git log -- lean/Fw/Wire/OpsGate.lean`). `lean/scripts/check.sh` green
(about 62 s). Standard axioms only. No edits to `Fw/Gate`, `Fw/Obs`, `Fw/Store`, `Fw/Ops`.

**Files:**
- `lean/Fw/Wire/OpsGate.lean` (namespace `Fw.Wire.OpsGate`): `GateDecision := guard d | queue why`, `gate i B σ x`
  (SpawnGuard first; a denial is final; else `admit` decides). This is the plan's `Fw.Ops.Gate`, placed under
  `Fw/Wire/` because of the write set.
- `lean/Fw/Wire/Sched.lean`: `inputOf`, `guardReply`, `gateName`, `gateReason`, `gateItem`, `opGate`; `ops.gate` is in
  `Fw.Wire.Sched.ops`/`handle`, so `Fw/Wire.lean` needed no change.
- `lean/Fw/Wire/SchedGolden.lean`: `gateCases` (17) → `packages/contracts/golden/ops/gate.jsonl`; `lake test` also
  fails if a reply's `guard` differs from `ops.spawn` on the same request (`gateGuardMismatches`).

**Contract:** request = `ops.spawn` fields + `budget`, `state`?, `item`? (absent: `{id: req.name}`, zero demand). The
item is judged as if enqueued now (`seq := next`, `enq := t`). Reply: `decision` allow/needsApproval/deny/queue,
`accepted`, `reason`, `guard` (the ops.spawn reply), `admit` (always computed, for shadow logs), `inv`.

**Theorems:** `gate_spec`, `gate_deny`, `gate_admit`, `gate_queue`, `gate_guard`, `gate_accepted_within`,
`gate_accepted_rate`, `gate_accepted_admit`, `gateName_accepted`.

**Open items:**
- PLAN.md l.323 calls `ops.gate` "the land-time gate on `Fw.Gate`"; the built op follows parallel plan §3.3 (spawn
  guard + Admit). The plan text needs a fix by plan-editor, or a separate land-gate op if that was meant.
- `inputOf` duplicates `opSpawn`'s decoding (Fw/Ops/Wire.lean was outside the write set); the golden cross-check
  guards drift. Refactor `opSpawn` to use one decoder when someone owns that file.
- Not added (outside the write set): `OpsGate.lean` to `check-partial.sh`, an `ops.gate` line in
  `golden/wire-requests.txt`, the `{admit,metrics,gate}` text in `scripts/SchedGolden.lean`'s docstring.
- TS caller: `apps/runner/hooks/spawn-guard.mjs` (E10, shadow mode), then `fw plan` / `fw job`.

**Read first:** the module doc of `Fw/Wire/OpsGate.lean`, then `gate.jsonl`.
