# hero-exit-proofs handoff

* Branch `worktree-wf_9bb60fc8-e86-1`, worktree `.claude/worktrees/wf_9bb60fc8-e86-1`. Finish commit 0dd947446
  (main merged at 90a159471); this handoff is in the next commit.
* CI runs: none (the task allows no CI or phone runs).
* Verified at 0dd947446:
  * `lean/scripts/check.sh` is green in a check slot, with the axiom check showing 0 failing.
  * The test scripts of @fw/site (164 files), @fw/contracts and @fw/runner pass, as does `scripts/ci-paths.test.mjs`.
  * `fw plan lint` prints no writesClosure error.
* Done:
  * Ledger row n 6 is `proved` with an empty missingWhy. `HeroExitWork` proves the R2 style saving
    (`cr_lane_style_saving`) and the WebKit edge cost (`wk_edge_layout`, `edgeFrames_le_starts`).
  * The `.proofs` evidence in `Gen.lean` (`threadedEvidence`) is computed from `why`, with two `#guard`s.
  * Model fix: the cue reads `--exit-opacity` (snapshot `.scroll-cue`), so `exitFade` on the cue is modelled.
    `animCount` is `N + 3` in the phone band and `N + 4` above, and `edgeCount` is `N + 3` / `N + 4`.
    `cr_lane_mixed` was restated for both bands. The note section "Model fix" has the table.
  * `Gen.run` was re-run. hero.exit:threaded is `enter` with blockers `[]`. Only `v2-proved.decisions.jsonl` changed.
* Open:
  * RG11 is CONFIRMED only for h − v ≥ 1 with a fixed scrollport.
  * The WebKit blur-kernel layout on interior frames is INFERRED and not modelled.
  * The data-exit-live handover frames are not modelled.
  * `cueOpacity` is not in the golden `settled` list, because adding it needs `threaded.ts` and its test.
* Read first: `research/notes/2026/10-2x-hero-exit-proofs.md`, then `HeroExitOpt.animCount` and `HeroExitWork`.
* To regenerate, run `lake env lean <file>` from `lean/` on a file holding `import Fw.Preset.Gen` and
  `#eval Fw.Preset.Gen.run []`.
