Branch: worktree-wf_07d103dc-24e-1 (CI branch ci/columns-final-scale). Worktree: .claude/worktrees/wf_07d103dc-24e-1
Last commit: `git log -1` on the branch. Pushes used: 2 of 3 (first 7e7ca6a82; second is the final commit).
CI runs: 40153993443 (lean, first push) failed: init-cost lint and footprint rows, both fixed afterwards; second push run id is in the report. Gate, Chromium counts and WebKit Simulator counts are lead dispatches (commands in the report), not started.
Verified locally (not a result): sh lean/scripts/check.sh green; @fw/site test 146 files pass, typecheck clean, compose.test, land-inputs, ci-paths pass; dry land with --allow lean/Fw/Ci/Trigger.lean prints VERDICT dry columns-final-scale (without --allow: VERDICT scope, one file, lean/Fw/Ci/Trigger.lean).
Open: the three dispatches, the look-review step (lead), the note's Runs section once run ids exist.

- Flag: `morph.columns:final-scale` (visClass L). Up to 1000 px the columns keep the final-width layout; CSS `translateX(...) translateY(offset) scale(a + (1-a)*--morph, 1)`. Constants `--cs-cf/--cs-a/--cs-d` written on mount and resize (index.tsx), `--col-i` static.
- Scale is horizontal only: fixed picture heights (Lean uniform_breaks_height). Above 1000 px the arm is the base (a = 0.69 at 1440); bound holds 314 to 1000 px.
- TS stand-in: the resize effect in index.tsx (DOM glue, no golden); scale.ts is checked by scale.golden.test.ts.
- Lean nullary defs are `(_ : Unit := ())` functions: the init-cost lint (scripts/InitCostLint.lean) fails with a recursion-depth error near 1645 start-time constants.
- Files outside the task writes: lean/Fw.lean, lean/Fw/Ci/Trigger.lean (scope refuses it; needs --allow), packages/contracts/golden/ci/triggers.jsonl (`lake test -- --write-ci-trigger-golden`), lean/scripts/check.sh, lean/scripts/MorphColumnsScaleGolden.lean, packages/contracts/golden/preset/look-change.candidates.jsonl (`Fw.Preset.Gen.run []`).
- Read first: research/notes/2026/10-2x-columns-final-scale.md, lean/Fw/Parts/MorphColumnsScale.lean.
