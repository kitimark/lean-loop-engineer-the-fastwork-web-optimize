# Handoff: slot-measure-exclusive

- Branch `worktree-wf_b45082e8-90f-1`, worktree `.claude/worktrees/wf_b45082e8-90f-1`; last sha: see `git log -1` on the
  branch (the handoff commit). No CI runs (Lean check, runner tests and land dry run locally through `fw slot`).
- Unit: Lean measure-window admission (`lean/Fw/Sup/MeasureWindow.lean`) with goldens in
  `packages/contracts/golden/sup/adapt.jsonl` (ops `window.*`), and `fw slot` following it.

## Verified
- Theorems: pass waits (`pass_live_waits`, `pass_live_no_admit`, `pass_start_quiet`, `pass_start_bounded`), gap fit
  (`gap_admit`, `gap_job_ends_before_pass`, `want_closes_gap`, `gap_measure_waits`), bounded wait (`after_deadline`,
  `openAt_deadline`, `deadline_fixed`, `capLease_within`, `window_keeps_older`, `wverdict_late_not_wait`).
- `sh lean/scripts/check.sh` green (axiom check included); `apps/runner` tests green; the TS window functions in
  `apps/runner/src/slot-core.ts` answer every `window.*` golden line.

## Open
- Lead step: switch `packages/measure-webkit/src/safari-local-lease.mjs` to `fw slot acquire --kind measure` plus
  `fw slot pass start|stop` (read only here).
- `apps/runner/src/slot-span.ts` adds `pass` to the span subcommands (in the write list since graph r284).
- Duration prediction is INFERRED: p90 of the last 20 local passing uncached `slot run <kind>` spans (at least 3). A
  job that runs past it can still overlap a pass; the pass's quiet check is the guard. `acquire` holders without
  `slot run` spans wait as `unknown` in a gap.
- A measure ticket has no priority like sim; it queues FIFO with the base verdict.
- Quiet rule follow-up: this Mac's idle floor was load 3-5 with no builders running (observed 20:27 on 2026-10-22),
  so a quiet check based on 1-min load needs a floor above that.

## Conventions
- `fw slot pass start` prints `VERDICT start|wait|gone pass`, exits 0/75/1. Events `pass-start`, `pass-refuse`,
  `pass-stop` go to `locks.jsonl`.
- Golden lines that fwcore builds are functions of `Unit` with `compiler.extract_closed false` (init-cost lint).

## Read first
`lean/Fw/Sup/MeasureWindow.lean`, `docs/team/tools/slot.md` (Measure window), `apps/runner/src/slot.ts` (`acquire`,
`passStartCli`, `passStopCli`, `windowLine`).
