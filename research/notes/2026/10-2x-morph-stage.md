# morph.stage (design rank 1 of 10-26-end-scroll-designs)

Status: measured on CI (Chromium and the gate); WebKit Simulator lanes waiting for wk-sim-hang. Look change, class L; T
and the look are for the user's review. Never a preset. Commit 13b09467c on ci/morph-stage (push 1 of 3).

- Flag `morph.stage:on`: the platform scene is `position: sticky` over T px of added page (T = 696 px at 1280x800,
  768 px at 390x844); `--morph` and `--morph-fade` run on `animation-timeline: scroll(root)` over [maxY - T, maxY].
  No scrollTo, no non-passive listener; the morph.mount and morph.tween scroll-jack is not mounted.
- Lean: `lean/Fw/Parts/MorphStage.lean` (trackT_ge, trackT_least, progress_inside, scene_held, armed_from_range_start,
  keyframes_end, key_eq_tween, stage_start_eq_tween, stage_end_eq_tween, write_at_crossing, no_scrollTo, no_nonpassive,
  jack_off_iff); golden `packages/contracts/golden/parts/morph-stage.jsonl`, replayed by `stage.golden.test.ts`.
- Local Playwright WebKit (debug run, not a result): ScrollTimeline present, --morph 0.93 at maxY - 50, 1 at maxY, nav
  width 1240 px at 1280 and 366 px at 390.

| item | run | state |
|---|---|---|
| lean | 40339107915 | success |
| breakpoint gate, both engines, default flags (push) | 40339108228 | success |
| breakpoint gate, both engines, fw=morph.stage:on | 40339272935 | FAIL |
| chromium-counts swipe-touch-v1 base, 3 runs | 40339630528 | filed |
| chromium-counts swipe-touch-v1 morph.stage:on, 3 runs | 40339622735 | filed |

## Gate with the flag: fail, cause named
Chromium 28 and WebKit 24 cells not ok, all in two parts: morph.mount (26) and morph.tween (14). Cause (read from
the merged readings): their anchors (`morph.mount` target, `morph.tween` scroller) have count 0 on the rewrite and 1 on
the original, because the flag does not mount the scroll-jack. Every other part passes. The Lean flag-delta list only
excuses style items, so a flag that unmounts a part has no way to pass the gate yet. Follow-up (not done here, a new
mechanism): a count delta for a flag that unmounts a part, with a theorem tying it to `jack_off_iff`.

## Chromium, base against flag (Lean reader offscreen-windows-cli.mjs, slack 0, 3 runs per arm)
End frame 574 on base, 670 with the flag.

| window | verdict |
|---|---|
| approach | noGain (less RecalcStyleCount 129 to 95, FireAnimationFrame 120 to 77; more LayoutCount 6 to 30, Paint 114 to 272, RasterTask 236 to 637) |
| end 0-19, 20-59, 60-119, 120+, finish | noData (not usable: the flag run has no frames in those windows from its end frame) |

## WebKit Simulator
Waiting: wk-sim-hang is not on main. Dispatch after it lands: `pnpm -s fw run --target rewrite --fw morph.stage:on --engines webkit --ref ci/morph-stage` (zones, 3 VMs) and the toolbar-throttle lane with the flag.
