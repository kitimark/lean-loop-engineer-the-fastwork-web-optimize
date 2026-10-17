# obs-signals handoff

State: committed on the worktree branch (see `git log -1` there); lead lands it. check.sh green, lake test all
passed, runner tests 263/263, incidents lint 0 errors. `fw next` on the live session: 11 NEXT lines.

## What exists
- `lean/Fw/Obs/Signals.lean`: the transcript-signal rule `classify p t f` over abstract facts (tool calls,
  background ids with start/end markers, handback, lead notes, procs) -> working | waitingOwnBg | handedBackHeld |
  handedBackDone | finished | idle | hung b. Theorems: classify_total, classify_det, state_working_iff_open,
  held_iff, classify_quiet_addEnd / endedB_mono (monotone in END), classify_metaFinished (meta.finished unused),
  golden_ok (8 real timelines, `decide +kernel`).
- `lean/Fw/Obs/Next.lean`: `resolve` feeds handbackSeen, children and producer-exited from Signals; `keep` =
  next != none, not meta.finished (keep_of_open_action, next_withMeta, resolve_handback).
- `lean/Fw/Wire/Obs.lean`: op `obs.signals`, `signals` field on obs.next facts, reply adds signal/handbackAt/keep;
  `SignalsGolden` writes/checks `packages/contracts/golden/obs/signals.jsonl` (39 checkpoints, FwTestMain).
- Golden times are SECONDS since 2026-10-17 23:00 +07:00; wire uses ms (`ms t = 1792252800000 + 1000 t`).
- TS glue: `apps/runner/src/watch-collect.ts` (stale meta.finished ignored on resume, bg ids from "Command running
  in background with ID:" text, `[killed]`, retention by pending ids / closed turns), `apps/runner/src/next.ts`
  (signalFactsOf, procOfCommand via ps command text, branch from meta.worktreeBranch, watch facts).
- Tests: `apps/runner/test/signals.test.ts` (synthetic fixtures). Incident inc-silent-stdin-bg has its regression.

## Conventions
- fwcore decides; TS only collects facts. New rule logic goes in Signals.lean first, then the golden, then TS.
- Golden regenerates via `SignalsGolden.run root true` (write mode); test mode diffs.

## Open items
- Live collector keeps 3 extra held agents with pending ids vs main (intended); watch for over-retention.
- The incidents lint warns that inc-silent-stdin-bg's procRef `cat` is still alive: the lead kills it.

## Read first
Signals.lean header doc, then `resolve` in Next.lean, then `signalFactsOf` in next.ts.
