# platform-fade-threaded (lean-prover)

- Branch `worktree-wf_a6ccf94a-185-1`, worktree `.claude/worktrees/wf_a6ccf94a-185-1`, pushed as `ci/platform-fade-threaded`.
- Last code sha: ecd75759 (Lean modules, goldens, TS variant, wiring).
- Runs: breakpoint-gate 39730956361 (engines both, fw platform:fade-threaded) in progress;
  webkit-sim base 39731023406 (cost=on, lag) in progress; webkit-sim flag 39731104953 (cost=on, lag, fw) queued.
  Dispatches used: 3 of 4.

## Verified
- `lean/Fw/Parts/PlatformFade.lean` (keyframes, `interp_eq`, `interp_blur`) and `PlatformFadeRun.lean` (`frame_eq`,
  `threaded_eq`, `retarget_from_shown`, `frame_blur_eq`, `ca_accepts`, `webkit_not_exact`) build; check.sh was green
  before the split into two modules.
- Site tests (110 files) and typecheck pass; `fade.test.ts` runs the golden vectors and replays original vs threaded.
- `scripts/ci-paths.test.mjs` passes: PlatformFade imports only MorphTween so the fwcore Main cone stays clean.

## Open
- Re-run check.sh after the split; read the gate and both webkit-sim runs (cost-report from artifacts).
- Note `research/notes/2026/10-2x-platform-fade-threaded.md`, ledger row n=43, preset regen, `results/platform-fade-threaded/report.json`.
- Merge main, dry land with `--allow` for: lean/Fw.lean, PlatformGolden.lean, FootprintData.lean, footprint*.json,
  preset decisions, morph.tween driver.ts and index.tsx, App.tsx, ledger, results/.

## Conventions
- Goldens: `PlatformGolden.fadeLines`, regenerated with `lake env lean --run` of the golden generator; never hand-edit.
- The driver skips per-frame `--morph-fade` only when `TweenEnv.fade` is set; settle writes it once.

## Read first
- `lean/Fw/Parts/PlatformFadeRun.lean` (theorems), `apps/site/src/parts/platform/fade.driver.ts`, `fade.test.ts`.
