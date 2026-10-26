# Handoff: verdict-evidence-audit

- Branch: worktree-wf_d1aac22c-7e1-1; worktree .claude/worktrees/wf_d1aac22c-7e1-1; last work commit 1f7973461 (main merged at 44d4b2301).
- CI runs: none (no CI measurement in this task).
- Verified: `lake build` green after merging main; TS tests offscreen, offscreen-windows, offscreen-webkit, touchlock pass;
  regenerated goldens only gained lines (complete-evidence rows unchanged).

## What changed
- `TouchLock`: `minSamples`, `known`, `cmpKnown`, `lookKnown` (`none` = undecided) with empty/short/complete theorems;
  golden ops `cmpKnown`, `lookKnown` and two more `look` rows in `touch-lock.jsonl`.
- `Offscreen`, `OffscreenWindows`, `OffscreenWebKit`: guards existed; added `gain_needs_runs`,
  `verdictOn_gain_needs_runs`, `armVerdicts_gain_needs_runs`, `armVerdicts_of_usable`, `gain_needs_evidence`,
  `passVerdict_gain_needs_runs`, `zoneVerdicts_gain_needs_evidence`, empty-side golden rows, TS test asserts.
- `VerdictEvidence.lean` (new): MorphEndCount win needs cost, Faithful region never passes with an empty arm.
- `Faithful/Golden`: rows "A/R recorded no zones".

## Open
- TS twin of `cmpKnown`/`lookKnown` in `packages/measure-webkit/src/touchlock.mjs` (outside writes).
- `faithful.verdict` with `zones: []` or 0-frame empty zones passes (Zone.lean/Wire.lean, outside writes).
- `NavFixedCounts.armOf`: a win among unusable cells (design question).

Read first: `research/notes/2026/10-2x-verdict-evidence-audit.md`.
