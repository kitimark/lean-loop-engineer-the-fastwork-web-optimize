# Handoff: gate-flag-deltas

## State
- Branch `worktree-wf_f4bb3c5b-525-1`. The rule, golden, TS twin, summary wiring, check.sh job and trigger rows are
  committed. The note is `research/notes/2026/10-25-gate-flag-deltas.md`.
- The breakpoint gate excuses a failing part reading when every failing item is an allowlisted
  (flag, part, role, property, orig, rewrite) tuple and its flag is in `header.flags.search`.

## Verified
- `Fw.Gate.FlagDelta` builds with standard axioms only. Theorems: `excused_only_flag_on`, `unlisted_item_fails`,
  `deltas_enumerated`, `flags_off_unchanged`, `readingVerdict_relabel`.
- `flag-delta.jsonl` passes its `--check`. `test/flag-delta.test.mjs` replays the golden and passes (23 tests together
  with exit.test).
- Offline re-judgement, per engine, of runs 40174477871 (morph.panel:rest) and 40156380619 (morph.columns:final-scale)
  gives pass in Chromium and WebKit with 0 remaining failures. Counts are in the note.

## Open
- `cli.mjs` was not in the writes, so readings excused by a flag delta show as `pass` in `readings-<engine>.json`.
  A follow-up could give them their own class there.
- The lead re-dispatches a gate run for morph.panel:rest after the land. No CI run was made in this task.

## Conventions
- Add a tuple only in Lean `deltas`, with its premise theorem, then regenerate the golden. Never edit the jsonl by hand.
- Read first: `lean/Fw/Gate/FlagDelta.lean`, then `applyFlagDeltas` in `packages/gate-breakpoints/src/summary.mjs`.
