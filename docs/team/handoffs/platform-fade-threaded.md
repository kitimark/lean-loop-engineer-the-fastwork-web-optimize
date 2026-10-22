# platform-fade-threaded (lean-prover)

- Branch `worktree-wf_a6ccf94a-185-1`, worktree `.claude/worktrees/wf_a6ccf94a-185-1`, CI branch `ci/platform-fade-threaded`.
- Code sha ecd75759; results commit follows it on the same branch.
- Runs: breakpoint-gate 39730956361 pass (engines both); webkit-sim base 39731023406 pass; webkit-sim flag
  39731104953 pass. Dispatches used: 3 of 4.

## Verified
- Lean: `PlatformFade.lean` (`interp_eq`, `interp_blur`), `PlatformFadeRun.lean` (`frame_eq`, `threaded_eq`,
  `retarget_from_shown`, `frame_blur_eq`, `ca_accepts`, `webkit_not_exact`, and the why of the no-win `recalc_same`,
  `writesT_sub`); check.sh green; axioms standard.
- Site tests (110 files) and typecheck pass; `fade.test.ts` checks goldens and replays original against threaded.
- Result: WebKit no-win. RecalculateStyles and Layout at the page end are equal within the pass gap, because the tween
  still writes the nav `--morph` on every frame that changes the fade (`recalc_same`).
- Ledger row n=44 `platform.fade-threaded` (n=43 went to accent.draw-one on main), preset regenerated, note and `results/platform-fade-threaded/report.json`.

## Open
- Chromium not measured (Blink keeps a blur effect on the main thread, compositor_animations.cc:408-416@f842f52).
- Paint and raster of the section need a real-GPU lane (mac-safari-measure or the phone).

## Conventions
- Goldens come from `PlatformGolden.fadeLines`; never hand-edit them.
- The tween driver skips per-frame `--morph-fade` only when `TweenEnv.fade` is set; a settle writes it once.

## Read first
- `research/notes/2026/10-2x-platform-fade-threaded.md`, `lean/Fw/Parts/PlatformFadeRun.lean`,
  `apps/site/src/parts/platform/fade.driver.ts`.
