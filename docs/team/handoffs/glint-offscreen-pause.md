branch: worktree-wf_4f5ecc25-48d-1 (CI branch ci/glint-offscreen-pause)
worktree: .claude/worktrees/wf_4f5ecc25-48d-1 (repo-relative; the absolute path holds a home directory)
last commit: see the git log (the CI branch tip is the commit pushed last)
CI runs: trajectory-probe 40092155958 SUCCESS (fw=platform.glint:offscreen-pause, engines both, all widths; inputs read back from step "trajectory inputs"); lean 40092156093 FAILED on footprint-diff.gen.json (regenerated since); lean re-run 40093964388 SUCCESS on a4b71aaae (ledger and preset commit after it is not pushed)
verified: check.sh green locally (slot), site test and typecheck green (slot), ci-paths 56 pass, runner land-inputs 60 pass, part-footprint --check green, plan lint 0 errors, ledger row 66 added
open: dry land without --allow refuses on scope (Visuals.tsx, index.tsx, FootprintData.lean, ledger.json; with --allow for those four it prints VERDICT dry); breakpoint gate and offscreen counts with the flag need a lead dispatch (pnpm -s fw run --gate --engines both --fw platform.glint:offscreen-pause --ref ci/glint-offscreen-pause)

## State
- Lean: lean/Fw/Parts/PlatformGlintPause.lean (WebKit SMIL time container model Cont/P/W; theorems visible_same_phase, local_time_same, same_run, variant_no_ticks_away, faithful_no_ticks_away, away_ticks_equal, window_gain). Golden: PlatformGlintPauseGolden.lean, lean/scripts/PlatformGlintPauseGolden.lean, packages/contracts/golden/parts/platform-glint-pause.jsonl.
- Site: apps/site/src/parts/platform.glint/pause.ts, pause.test.ts, part.json variant offscreen-pause; wiring in platform/Visuals.tsx (createPause in the observer callback, before the glint driver) and platform/index.tsx (glint on for faithful or offscreen-pause, glintPause only for the flag).
- Finding: the faithful arm already unmounts the animate pair when the ratio is below 0.35 (v implies h), so no SMIL ticks offscreen in faithful; the flag removes at most the ticks of the commit window. Expect no gain.

## Lead wires (not edited here)
- lean/Fw.lean: import Fw.Parts.PlatformGlintPause and import Fw.Parts.PlatformGlintPauseGolden
- lean/scripts/check.sh: job "platform-glint-pause golden check" lake env lean --run scripts/PlatformGlintPauseGolden.lean --check ../packages/contracts/golden/parts/platform-glint-pause.jsonl

## Conventions
- Generated files regenerated, not hand-edited: footprint.gen.json, FootprintData.lean (part-footprint --write), footprint-diff.gen.json (ContractsGolden --diff), golden/preset/v2-proved.decisions.jsonl (Fw.Preset.Gen.run []).
- Outside the task writes: platform/Visuals.tsx, platform/index.tsx, lean/scripts/PlatformGlintPauseGolden.lean, the generated files above, research/findings/ledger.json.
