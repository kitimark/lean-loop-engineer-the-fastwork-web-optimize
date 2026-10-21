# sup-baseline handoff (measure-engineer)

Branch `worktree-wf_f3ac4663-d82-1`; state = the commit that adds this file (`git log -1 -- docs/team/handoffs/sup-baseline.md`).

## Done (stage 0 of the daemon design: logs, sampler, verdict, first-day note)
- Lean `Fw.Obs.Health.Res` (lean/Fw/Obs/Health.lean, end of file): `classify` (argv0 basename allowlist `kindTable`), `verdict` quiet/busy/pressured,
  theorems `verdict_rank_mono`, `quiet_no_heavy`, `quiet_iff`, `pressured_iff`, `classify_listed`. Golden: packages/contracts/golden/obs/sup-health.jsonl
  from lean/scripts/SupHealthGolden.lean (check.sh job "sup-health golden check"). `Params` defaults are first guesses (swap 90, compressor 50, free 15, load 2.00).
- Lock events (one jsonl line per acquire/release, heavy also refuse; no path, no args, no owner) in `<main>/.fw-console/locks.jsonl`:
  scripts/heavy-lock.mjs, scripts/lake-slot-lib.sh (kinds build/group), scripts/sim-lock.sh. Off with FW_LOCK_EVENTS=off or CI; FW_LOCK_EVENTS_FILE overrides.
- Sampler: apps/runner/src/watch-collect.ts `ensureSampler` (called by `collectSnapshot`, 20 s, unref'd timer, 15 s mtime dedupe) writes
  `.fw-console/sup-samples.jsonl` (`sampleOnce`, `buildSample`). FW_SUP_SAMPLER=off disables. TS classifier/verdict replay the golden.
- Note: research/notes/2026/10-2x-sup-baseline.md is GENERATED: `node apps/runner/src/sup-report.ts --dir <main>/.fw-console --out research/notes/2026/10-2x-sup-baseline.md`.

## Verified
check.sh exit 0; apps/runner `pnpm test`; scripts/lake-slot.test.mjs, heavy-lock.test.mjs, ci-paths.test.mjs; land-inputs test; `fw land --dry` VERDICT in the report.

## Open
- The running watch process picks the sampler up only after a restart on the landed code; the 3-day collection and its conclusions are follow-ups.
  After day 3 re-run the generator, then revise `Params` in Lean (golden regenerates) if the shares look wrong.
- lake-slot with events on runs the command as a child (no exec); the pid is the calling shell's (`$$`); times are ms where `date` has %N (this Mac), else whole seconds.
- `webkit` cannot tell the Simulator's WebKit helpers from a user's Safari (same names). mac-safari-measure can reuse `verdict` and `classify` unchanged.
- TS stand-ins: classifier, verdict (golden-checked), note generator (sup-report.ts).

## Conventions
Events are repo-relative, reduced, allowlisted rows; raw files stay under `.fw-console/` (gitignored). Read first: the note, then Health.lean `Res`.
