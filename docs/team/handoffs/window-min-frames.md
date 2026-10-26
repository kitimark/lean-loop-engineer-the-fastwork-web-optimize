# window-min-frames handoff

Branch: worktree-wf_f0e38840-978-1, worktree .claude/worktrees/wf_f0e38840-978-1
Last code commit: 2ee2c328c (Lean, golden, TS); note ee0b192d3; this handoff and the main merge follow.
CI runs: none (accepted limit). Re-read used runs 40339630528 (base) and 40339622735 (morph.stage), both complete.

## State
* Lean `lean/Fw/Measure/OffscreenWindows.lean:553-700`: `minEnd120`, `wholeWindows`, `minFrames` (34, 20, 40, 60, 20,
  174), `framesOk`, `minVerdicts` and the theorems `minVerdicts_needs_frames`, `minVerdicts_short_noData`,
  `minVerdicts_short_not_gain`, `minVerdicts_eq_or_noData`, `minVerdicts_gain_own`, `minVerdicts_eq_own`.
* Short-run rule: a run below `minFrames` makes the window noData (no drop). The drop alternative is `dropVerdicts` in
  `OffscreenWindowsGolden.lean`, with a `#guard` counterexample where it turns noGain into gain.
* Golden `op: "min"` (one line per own case, 14) plus `minFrames` on the constants line. TS `minVerdicts`, `MIN_FRAMES`
  in `packages/measure-chromium/src/offscreen-windows.mjs` replay it; `summarizeArm` and the CLI table use it.
* morph.stage re-read in `research/notes/2026/10-2x-window-min-frames.md`: end 0-19 gain on 3 frames becomes noData;
  approach noGain; finish noData (37 of 174 frames).

## Verified
Lean build, `#guard`s, golden check, measure-chromium test (109 pass), ci-paths test, land-inputs test. check.sh, plan
lint, dry land and review gate: see the report.

## Open
* Revise `minEnd120` after profile-end-tail lands (rule in the note, section "Revision after profile-end-tail").
* Raw counts.json for the re-read are CI artifacts (not in git); fetch them with `gh run download` for the run ids above.

## Read first
The note, then `OffscreenWindows.lean` from line 553.
