branch: worktree-wf_4f5ecc25-48d-1 (CI branch ci/glint-offscreen-pause)
worktree: .claude/worktrees/wf_4f5ecc25-48d-1 (repo-relative; the absolute path holds a home directory)
last commit: 3b13871884663232f1b9d71e015cbd77003b9757 (CI request commit; work in ae6b2e539)
CI runs: trajectory-probe 40092155958 in_progress (fw=platform.glint:offscreen-pause, engines=both, all widths); lean 40092156093 in_progress
verified: Lean file and golden build (lake build Fw.Parts.PlatformGlintPause*), golden check green, vitest src/parts/platform.glint 246 pass, part-footprint --check green
open: local slot test + check.sh not finished; merge main; fw plan lint; dry land; review ready; counts/gate with the flag need a lead dispatch (see report)

## State
- Lean: lean/Fw/Parts/PlatformGlintPause.lean (WebKit SMIL time container model Cont/P/W, theorems visible_same_phase, local_time_same, same_run, variant_no_ticks_away, faithful_no_ticks_away, away_ticks_equal, window_gain). Golden: PlatformGlintPauseGolden.lean, lean/scripts/PlatformGlintPauseGolden.lean, packages/contracts/golden/parts/platform-glint-pause.jsonl.
- Site: apps/site/src/parts/platform.glint/pause.ts, pause.test.ts, part.json variant offscreen-pause; wiring in platform/Visuals.tsx (createPause in the observer callback, before the glint driver) and platform/index.tsx (glint on for faithful or offscreen-pause, glintPause only for the flag).
- Finding: the faithful arm already unmounts the animate pair when the ratio is below 0.35 (v implies h), so no SMIL ticks offscreen in faithful; the flag removes at most the ticks of the commit window. Expect no gain.

## Lead wires (not edited here)
- lean/Fw.lean: import Fw.Parts.PlatformGlintPause and import Fw.Parts.PlatformGlintPauseGolden
- lean/scripts/check.sh: job "platform-glint-pause golden check" lake env lean --run scripts/PlatformGlintPauseGolden.lean --check ../packages/contracts/golden/parts/platform-glint-pause.jsonl

## Conventions
- Generated files regenerated, not hand-edited: footprint.gen.json, FootprintData.lean (part-footprint --write), golden/preset/v2-proved.decisions.jsonl (Fw.Preset.Gen.run []).
