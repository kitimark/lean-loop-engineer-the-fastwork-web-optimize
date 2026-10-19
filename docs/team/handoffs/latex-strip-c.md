# latex-strip-c (Step C of lean-latex-removal)

- **State:** branch `worktree-wf_6aea450e-61b-1`; tool `7c6f4349`, header fix `6bdcd95e`, sweep `881197cf`..`f0f49fa6` (12 commits by `lean/` directory).
- **Tool:** `node scripts/latex-strip.mjs <files>` rewrites in place; `--check <files>` exits 1 while a doc comment holds `$$`.
  Tests: `node --test scripts/latex-strip.test.mjs` (22 cases, each also checks that a second pass changes nothing).
  JS stand-in with no Lean golden; it holds no project decision, only text rewriting.
- **Rules:** only `/-- -/` and `/-! -/` bodies change (strings, raw strings, interpolation, chars, nested comments are lexed).
  A `$$…$$` block is removed and its lead-in (`:`, `i.e.`) becomes a full stop. Inline `$…$` becomes a Unicode code span
  (`k ≥ 1`); it is removed only when it has no plain form (0 cases in the sweep).
- **Accepted limit:** a following `where`/`with`/`so` clause that holds math is dropped with its block; in the samples
  checked it only defined symbols of that block.
- **Counts (included files):** 259 files, 195 held math; doc `$$` blocks 7758 → 0; doc comments 9484 → 9484 (none deleted).
  `Fw/Ops/Wait.lean` keeps 3 shell `$$` in `#guard` strings (code). Generated, skipped (0 `$$` each): Console/PreviewFacts,
  Faithful/Measured, Gate/ShardObs, Ops/LakeJobsGen.
- **Excluded (open tasks), doc `$$` blocks left = 1944:** Ci/Budget 113, Cancel 9, Intent 79, Trigger 38, Verdict 37,
  Wire 7; Console/LandQueue 37, PreviewOwner 84; Engine/Chromium 137, Compose 34, Core 95, Keys 17, Lessons 26, Visual 76,
  WebKit 134; Gate/Coverage 49; Ops/Premise 101; Parts/HeroCountdown 73, HeroCountdownHidden 44, HeroCountdownOpt 61,
  HeroExitOpt 93, MorphMount 22, MorphMountGolden 7, MorphMountOpt 85, MorphPanel 18, MorphPanelOpt 93, MorphTween 37,
  MorphTweenOpt 122; Preset/Gen 34; Site/Stage 46, StageMode 55; Wire/GateDeclared 15, GateSpeedGolden 1, Obs 17,
  OpsGate 11, Plan 1, Sched 31, ShardGolden 4, Store 1. Excluded with 0: Fw.lean, Ci/Golden, Ops/Golden (2 `$$` in code),
  FootprintData/Rows, other Wire files.
- **Mutant patches:** the 9 whose context moved (SpawnGuard/name-reuse + 8) were regenerated (mutant at HEAD, stripped,
  diffed against the swept file; +/- lines unchanged). `git apply --check --directory=lean` passes for all 12.
- **Hand edits:** LaTeX in code spans became Unicode (Sched/Admit 1274, Measure/WktrLayout 98, 238). `MathView.lean:16`
  keeps `\mathrm{f}(…)`: it names the LaTeX MathView emits (Step D).
- **Verified at f0f49fa6:** `lake build` 550 jobs green; `sh lean/scripts/check.sh` green (axioms 46164, 0 failing; every
  golden `--check` up to date; tree clean after). MathView: 9745 entries before and after, stmtHash set diff empty both
  ways; `$$` only in excluded modules. `--module` Fw.Sched.Admit 197/197, Fw.Measure.WktrLayout 41/41 same stmtHash.
  `--check` 0 on the 259 files; tool tests 22/22; ci-paths 40/40; runner land-inputs 54/54.
- **Open:** (1) after each excluded task lands, run the tool and `--check` on its files; (2) comment-sicko prose pass
  (some sentences read as fragments, e.g. Gate/Schedule); (3) Step D deletes the LaTeX guardrails (lint, MathView fields).
- **Read first:** `scripts/latex-strip.mjs` (the `stripMath` comment explains the rules), then the excluded list above.
