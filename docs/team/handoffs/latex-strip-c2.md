# latex-strip-c2 (finish the Step C sweep on the files latex-strip-c excluded)

- **State:** branch `worktree-wf_db3565e2-fda-1`; sweep `ca679703`..`1aa6500b` (6 commits by `lean/` directory), on base `8eb17e4f`.
- **Run:** `node scripts/latex-strip.mjs <38 files>` (tool unchanged). No hand edits: no LaTeX command, `_{` or `^{` is
  left in any doc comment of the 38 files, code spans included. `Ops/Premise` keeps LaTeX in `statement := r"…"` strings
  (code, out of scope).
- **Doc `$$` blocks before → after (0 each):** Ci/Budget 139, Cancel 9, Intent 79, Verdict 37, Wire 7; Console/LandQueue
  70, LandTier 1, PreviewOwner 84; Engine/Chromium 137, Compose 34, Core 95, Keys 17, Lessons 26, Visual 76, WebKit 134;
  Gate/Coverage 49; Ops/Premise 101; Parts/HeroCountdown 73, HeroCountdownHidden 44, HeroCountdownOpt 61, HeroExitOpt 93,
  MorphMount 22, MorphMountGolden 7, MorphMountOpt 85, MorphPanel 18, MorphPanelOpt 93, MorphTween 37, MorphTweenOpt 121;
  Preset/Gen 34; Site/Stage 46, StageMode 55; Wire/GateDeclared 15, GateSpeedGolden 1, Obs 17, OpsGate 11, Plan 1,
  Sched 31, ShardGolden 4. Total 1964 → 0. Doc comments 2662 → 2662 (none deleted). Diff: +1337 / −5267 lines.
- **Mutant patches:** none of the 12 targets one of the 38 files; none regenerated. `git apply --check --directory=lean`
  passes for all 12.
- **Verified at `1aa6500b`:** `lake build` green (592 jobs); MathView 10951 entries before and after, (name, kind,
  stmtHash) set diff empty both ways; doc `$$` in MathView only in `Fw.Ci.Trigger` (38 entries) after, 31 modules before.
  `--check` exits 0 on the 38 files; tool tests 22/22; ci-paths 41/41; runner land-inputs 55/55; `sh lean/scripts/check.sh` green ("all lean/ gates
  green", mathview lint included; tree clean after).
- **Open:** (1) `lean/Fw/Ci/Trigger.lean` (38 blocks) and `lean/Fw/Wire/Store.lean` (1) after trajectory-probe lands:
  run the tool, then `--check`; (2) the comment-sicko prose pass from latex-strip-c open item (2); (3) Step D.
- **Note:** the pre-commit hook (checkmap) runs `lake build`; never run a second build while committing Lean files
  (two concurrent builds failed with `permission denied` on an `.ilean`).
- **Read first:** `docs/team/handoffs/latex-strip-c.md`, then `scripts/latex-strip.mjs`.
