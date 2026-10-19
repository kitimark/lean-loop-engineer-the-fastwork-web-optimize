# waapi-touch-arm handoff

State: branch `worktree-wf_e80309b1-ad5-2`, CI branch `ci/waapi-touch-arm` (pushed at bcf9c7e0). The final commit is the branch head.

Verified:
- `lean/Fw/Parts/MorphTweenOpt.lean` builds and makes the rows a function of the profile (`rowsFor`, `predProfile`, `compPred`). The lemma "no pushes, so `=o`" is `noPush_eqO`, and every swipe-v1 row predicts `=o` (`swipeRows_eqO`). A push gives `<o` (`raf_sum_lt`, `tween_of_push`).
- The goldens are generated from Lean and checked by `#guard include_str`:
  - `morph-tween-waapi.jsonl` holds the swipe-touch-v1 rows.
  - `morph-tween-waapi.swipe-v1.jsonl` is a new file and holds the swipe-v1 rows, all `=o`.
- engine-check, MEASURED:
  - swipe-v1 (runs 39295469515 and 39295561652): 3 pass, 0 model-bug, 3 unusable. The composite row passes now.
  - swipe-touch-v1 (runs 39312308173 and 39312313059, 3 runs each): 1 pass, 2 model-bug, 3 unusable.
  - The touch arm saves 33 rAF callbacks per run.
  - No frame-498 quarantine was needed.
- `sh lean/scripts/check.sh` is green. Tests pass: runner (with typecheck and land-inputs), site morph.tween, ci-paths.

Open:
- The touch rows Paint `=o` and compositeFailedBits `<o` are model-bugs. The cause is a one-frame lead of the WAAPI start, because the timeline time is snapped to the frame grid (Blink animation_clock.cc:55-88). See `start_eq_refuted` and `lead_within_frame`.
- `WaapiPremises.start_eq` (R5) is refuted in Chromium. `pred_sound` needs a one-frame bound.
- morph-layers owns `apps/site/src/parts/morph.tween/waapi.golden.test.ts`. That test could also pin the swipe-v1 file.

Conventions:
- To regenerate the goldens, run a `main` that writes `goldenJsonl` and `swipeJsonl` with `lake env lean --run`. The include guards are the check.
- To get the verdicts again, run `node packages/engine-check/src/cli.mjs --rows <golden> --runs <base>,<arm>`.

Read first:
- `research/notes/2026/10-20-waapi-touch-arm.md`
- `results/waapi-touch-arm/runs.json`
