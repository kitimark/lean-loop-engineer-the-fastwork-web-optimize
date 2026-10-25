Branch: worktree-wf_07d103dc-24e-1 (CI branch ci/columns-final-scale, pushed at 7e7ca6a82). Worktree: .claude/worktrees/wf_07d103dc-24e-1
Last commit: see `git log -1`. Pushes used: 1 of 3.
CI runs: push run 40153993443 (lean) started; all other push runs skipped by path filters. Gate, Chromium counts and WebKit Simulator counts need the lead (not started).
Verified: Lean file builds with no sorry (MorphColumnsScale.lean); golden check job in check.sh; site test for morph.columns passes (scale.golden.test.ts, media.test.ts); typecheck clean.
Open: gate and count runs (dispatch commands in the report), look-review step (lead posts), full check.sh at the final commit, dry land.

- Flag: `morph.columns:final-scale` (visClass L). Up to 1000 px the columns keep the final-width layout; CSS `translateX(...) translateY(offset) scale(a + (1-a)*--morph, 1)`. Constants `--cs-cf/--cs-a/--cs-d` written on mount and resize (index.tsx), `--col-i` static.
- Scale is horizontal only: fixed picture heights (Lean uniform_breaks_height). Above 1000 px the arm is the base (a = 0.69 at 1440).
- TS stand-in: the resize effect in index.tsx (DOM glue, no golden); scale.ts is checked by scale.golden.test.ts.
- Files outside the task writes: lean/Fw.lean, lean/Fw/Ci/Trigger.lean, packages/contracts/golden/ci/triggers.jsonl (regenerated with `lake test -- --write-ci-trigger-golden`), lean/scripts/check.sh, lean/scripts/MorphColumnsScaleGolden.lean, packages/contracts/golden/preset/look-change.candidates.jsonl (Fw.Preset.Gen.run []).
- Read first: research/notes/2026/10-2x-columns-final-scale.md, lean/Fw/Parts/MorphColumnsScale.lean.
