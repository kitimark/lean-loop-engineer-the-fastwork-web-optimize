Branch: worktree-wf_09ed78f0-21c-1
Worktree: .claude/worktrees/wf_09ed78f0-21c-1
CI runs: none (no CI push; the task is local Lean + runner code)

State: slot run spans split and keyed per command.
- Lean: `Fw.Obs.Timing.SlotKey` (end of lean/Fw/Obs/Timing.lean): `cmdKey`, `capKey` (cap 24), `runStep`, `waitStep`; theorems for the
  cap (`capKey_seen/_full/_room/_some`), `cmdKey_nil`, `wait_ne_run`; 14 golden cases `packages/contracts/golden/obs/slot-key.jsonl`
  (lean/scripts/SlotKeyGolden.lean, a `check.sh` job line).
- TS: apps/runner/src/slot-span.ts (port, golden-replayed), slot.ts `run` writes `slot wait <kind>` (acquire to grant) and
  `slot run <kind> <cmd>` (grant to exit; ` dry`, ` cached` suffixes kept); fw.ts and fw-main.ts no longer wrap `slot run` in a whole-process span.
- Seen keys for the cap come from the last 2 MB of timings.jsonl (I/O glue, none under vitest).

Verified: vitest slot-span, span-names, slot tests; lean/Fw/Obs/Timing.lean compiles; golden check.
Alert of 2026-10-22 16:51: test/slot-span.test.ts replays the 53 full samples through fwcore: pooled key gives slow (reproduced),
the command key has no history so it is noBaseline, and ok once five runs of that command exist.

Limits: recorded samples carry no command, so they cannot be replayed to keys (the test replays the golden commands and the
alert durations). Past samples keep the old key. `pnpm exec`/`dlx` unwraps one level only.
Writes outside the task's graph writes: apps/runner/src/fw.ts, apps/runner/src/fw-main.ts, apps/runner/test/span-names.test.ts,
lean/scripts/SlotKeyGolden.lean, lean/scripts/check.sh.
Read first: the SlotKey section of lean/Fw/Obs/Timing.lean, then apps/runner/src/slot-span.ts.
