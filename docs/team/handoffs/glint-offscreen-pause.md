branch: worktree-wf_4f5ecc25-48d-1 (CI branch ci/glint-offscreen-pause)
worktree: .claude/worktrees/wf_4f5ecc25-48d-1
last commit: the CI branch tip
CI runs: trajectory-probe 40092155958 SUCCESS (fw=platform.glint:offscreen-pause, engines both, all widths; inputs read back from step "trajectory inputs"); lean 40092156093 FAILED on footprint-diff.gen.json (regenerated since); lean re-run 40093964388 SUCCESS on a4b71aaae (ledger and preset commit after it is not pushed)
verified: check.sh green locally (slot), site test and typecheck green (slot), ci-paths 56 pass, runner land-inputs 60 pass, part-footprint --check green, plan lint: 2 errors, neither in this task's writes, ledger row 71 added

## State
- Lean: lean/Fw/Parts/PlatformGlintPause.lean (WebKit SMIL time container model Cont/P/W; theorems visible_same_phase, local_time_same, same_run, variant_no_ticks_away, faithful_no_ticks_away, away_ticks_equal, window_gain). Golden: PlatformGlintPauseGolden.lean, lean/scripts/PlatformGlintPauseGolden.lean, packages/contracts/golden/parts/platform-glint-pause.jsonl.
- Site: apps/site/src/parts/platform.glint/pause.ts, pause.test.ts, part.json variant offscreen-pause; wiring in platform/Visuals.tsx (createPause in the observer callback, before the glint driver) and platform/index.tsx (glint on for faithful or offscreen-pause, glintPause only for the flag).
- Finding: the faithful arm already unmounts the animate pair when the ratio is below 0.35 (v implies h), so no SMIL ticks offscreen in faithful; the flag removes at most the ticks of the commit window. Expect no gain.


## Conventions
- Generated files regenerated, not hand-edited: footprint.gen.json, FootprintData.lean (part-footprint --write), footprint-diff.gen.json (ContractsGolden --diff), golden/preset/v2-proved.decisions.jsonl (Fw.Preset.Gen.run []).
- Outside the task writes: platform/Visuals.tsx, platform/index.tsx, lean/scripts/PlatformGlintPauseGolden.lean, the generated files above, research/findings/ledger.json.

## Round 2
- Result: negative. The flag gains the commit window only (window_gain). Ledger row 71 status says so. Gate with the flag: not run (followUp). Offscreen counts: task offscreen-count-lane.
- Wiring done on the branch: lean/Fw.lean imports, check.sh job, lean.yml trigger row + triggers.jsonl regenerated.
- open: research/notes/2026/10-2x-webkit-throttles.md rank 4 still says "Less work"; correct to "no gain beyond the commit window" (not in this task's writes).
