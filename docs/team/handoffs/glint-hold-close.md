# glint-hold-close handoff

- Branch `worktree-wf_72856401-589-1`, worktree `.claude/worktrees/wf_72856401-589-1`, rule commit d7d05a78b, main
  merged after it (see `git log`).
- CI runs: none (the task allows none).

## Verified
- `Fw.Parts.PlatformGlintPause.resume_seek_forward` (+ `_start`, `fwd_step`, `seeks`): every resume seek targets an elapsed
  time at or after the frozen one, given nondecreasing observation times. Linked in the ledger row `leanFor` and
  `Fw.Preset.Gen.holdRowNames` (checked by `Gen.run`, `holdLinkGaps`). missingWhy[1] removed.
- Look rule `Fw.Preset.Gen.lookMet` = `V2Proved.exactLook` (class e/eS) or accepted user look.
  `entry_enter_iff_ok_of_exact` (class E), `entry_enter_iff_ok_of_noGaps` (every decided flag in `agreeScope`:
  class E or unclassified, minus `lookExceptions`). `Gen.run` fails on `entryGaps` and `staleLookExceptions`.
- Lead decision applied: `engine.scroll:unthrottle` is the one listed exception (`Gen.lookExceptions`); it stays in
  `v2-proved`. Goldens unchanged by this step; `Gen.run --check` up to date.
- `check.sh` green after merging main; @fw/contracts, @fw/runner, @fw/site tests and typechecks pass; ci-paths 56/56.

## Open
- missingWhy[0] (Simulator zones) stays open: WKTR idle recalc answers another question (note section 4).
- Follow-up: classify `engine.scroll:unthrottle` as `e` in `engine.scroll/part.json` from its ledger row (outside this
  task's writes), then drop it from `lookExceptions`.
- hold-freeze `Gen.entry`: not yet, blockers `[proofs]`.

## Read first
`research/notes/2026/10-2x-glint-hold-close.md`, then `lean/Fw/Preset/Gen.lean` (`lookMet`, `agreeScope`, `entryGaps`).
