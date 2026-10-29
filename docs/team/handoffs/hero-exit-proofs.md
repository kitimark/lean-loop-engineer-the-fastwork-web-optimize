# hero-exit-proofs handoff

* Branch `worktree-wf_9bb60fc8-e86-1`, worktree `.claude/worktrees/wf_9bb60fc8-e86-1`, proofs commit d6174ba8c; the
  note and this handoff are in the next commit.
* CI runs: none (the task allows no CI or phone runs).
* Verified:
  * `lean/scripts/check.sh` is green in a check slot, with the axiom check showing 0 failing.
  * Site preset tests pass, as do the site test script (164 files) and typecheck.
  * Contracts tests pass, as do the apps/runner ledger-merge, ledger-alloc and land-inputs tests and
    `scripts/ci-paths.test.mjs`.
* Done:
  * `lean/Fw/Parts/HeroExitWork.lean` proves the R2 style saving (`cr_style_saving`, `cr_lane_style_saving`, with
    consumers counted from `heroTree`) and the WebKit edge-frame cost (`wk_edge_layout`, `filter_edge`,
    `opacity_edge`, `edgeFrames_le_starts`).
  * Ledger row n 6 is `proved` with an empty missingWhy.
  * `Fw.Preset.Gen.run` moved hero.exit:threaded from `not yet` to `enter`.
* Open:
  * `lean/Fw/Preset/Gen.lean:698-705` still says the missingWhy is open, and that path is outside this task's writes.
  * The cue's `exitFade` is missing from the HeroExitOpt anim lists: one more edge unit.
  * Interior blur-kernel layout and the handover frames are not modelled.
  * RG11 is CONFIRMED only for h − v ≥ 1 with a fixed scrollport.
* Writes outside the allowed list: `apps/site/src/registry/presets/v2-proved.json`, written by `Gen.run` together
  with the golden. `check.sh` requires the two files to match.
* Read first: `research/notes/2026/10-2x-hero-exit-proofs.md`, then the module header of `HeroExitWork.lean`.
* Regenerate the preset from `lean/` with `lake env lean <file>` on a file holding
  `import Fw.Preset.Gen` and `#eval Fw.Preset.Gen.run []`. Never edit the preset by hand.
