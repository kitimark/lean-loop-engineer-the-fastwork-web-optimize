# morph.stage (design rank 1 of 10-26-end-scroll-designs)

Status: measured on CI (Chromium and the gate); WebKit Simulator zones blocked by runner loss (no flag VM finished in 6 of 6 tries). Look change, class L; T
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

## Gate with the flag: pass (round 2, run 40366243322)
Round 1 (40339272935) failed 28 Chromium and 24 WebKit cells, all in morph.mount and morph.tween: the flag leaves their
anchors (`morph-mount`, `morph-tween`) unmounted, count 0 on the rewrite against 1 on the original.
Now `Fw.Gate.FlagDelta.replacedParts` has two entries (stage-mount, stage-tween; flag morph.stage:on; premise
`Fw.Parts.MorphStage.stage_unmounts_anchors`, which states that with the stage on `morph-mount` and `morph-tween` are
not mounted; `stage_keeps_others` says no other anchor is unmounted; `faithful_mounts_anchors` the off side). The
gate (both engines, fw=morph.stage:on) passes. Items excused: only `target[-1].count` of morph.mount and
`scroller[-1].count` of morph.tween (Chromium 196 each, WebKit 188 each); no other item was excused.
Accepted limit: a Lean look field on ReplacedPart is a follow-up.

## Chromium, base against flag (round 2, swipe-touch-v1 with the swipe-end tail, 3 runs per arm, commit 8f2f726bf)
Base run 40366273179, flag run 40366262655. Lean reader offscreen-windows-cli.mjs (slack 0) with minFrames
34/20/40/60/20/174. End frame 574 (base), 670 (flag); each window starts at the run's own end frame.

| window | stage |
|---|---|
| approach | noGain; less: RecalcStyleCount 129 to 95, FireAnimationFrame 120 to 77; more: LayoutCount 6 to 30, Paint 114 to 272, RasterTask 236 to 637, PaintImage 137 to 617 [34 frames, min 34] |
| end 0-19 | gain; less: RecalcStyleCount 43 to 22, LayoutCount 21 to 1, Paint 335 to 43, RasterTask 517 to 20, PaintImage 495 to 92, FireAnimationFrame 43 to 40 [20 frames, min 20] |
| end 20-59 | gain; less: LayoutCount 25 to 0, Paint 252 to 80, RasterTask 454 to 0, PaintImage 454 to 160, FireAnimationFrame 141 to 17 [40 frames, min 40] |
| end 60-119 | gain; less: FireAnimationFrame 56 to 54 [60 frames, min 60] |
| end 120+ | gain; less: FireAnimationFrame 39 to 37 [47 frames, min 20] |
| finish | gain; less: RecalcStyleCount 319 to 264, LayoutCount 52 to 31, Paint 915 to 609, RasterTask 1207 to 657, PaintImage 1514 to 1297, FireAnimationFrame 400 to 225 [201 frames, min 174] |

Reading: the approach window has more LayoutCount, Paint, RasterTask and PaintImage (the sticky scene and the scroll
timeline do work the base does not do while the page approaches the end) and less RecalcStyleCount and
FireAnimationFrame: noGain. Every window from the end frame has a counter less and none more with the minimum frames
met: gain. All six windows have enough frames (the 120+ window has 47 against 20).

## WebKit Simulator zones (webkit-sim, minVms 3): blocked, undecided
Dispatches: base 40366306645 (3 VMs after reruns, commit 8f2f726bf); flag 40366323523 (8f2f726bf, 0 VMs) and, after merging
wk-loop-freeze (freeze-aware stall clock), flag 40429988675 (8324e9f89, 0 of 3 VMs: r1, r2, r3 all cancelled at the 58 min
limit). No `webkit-sim-r` artifact exists for either flag run, so the zone reader has nothing to read on the flag side and
every zone stays undecided on the Lean minVms 3 rule (never a win). The base harness commit is older than the flag run's.

Cause (MEASURED from the sim-tick console tails of 40429988675 and the job log of 40366323523; base 40366306645 compared at the same steps):
- Runner side, r1 and r3 of 40429988675 and r1 of 40366323523: the Safari tab never attached ("no tab after 6 to 115 s", openurl
  asked again 7 to 19 times, `warm-up ... Runtime.evaluate timed out after 120000 ms`), then `simctl shutdown failed (ETIMEDOUT)`
  and exit 4 / exit 1. The flag page had not loaded, so the flag cannot be the cause. `event loop blocked ... host calls running: []`
  and, in r1 of 40429988675, `the host held the process (it used 0 s of cpu in 65 s)` are the VM-freeze marks of
  research/notes/2026/10-2x-wk-loop-freeze.md.
- r2 of 40429988675 loaded the flag page: warm-up, census at y 0, 1500, 3000, 4500 (145 layers, 149 MB, within the base's
  141 to 146 layers and 149 to 160 MB), then `Runtime.evaluate timed out` twice after y 4500 with `the host held the
  process (0 s of cpu in 191 s)` just before the first. The base shows the same timeout after y 4500 (r1 tick 5, r3 tick 3 and 4 of 40366306645) and recovered by a
  fresh load, so it is not a flag signature; the two flag hangs hit the freeze marks, so the cause is the VM, not the page.
  Not proved: a local Web Inspector timeline was not taken (no page-side signature to chase), so a flag share in r2's second hang is not excluded.
Verdict: WebKit zones blocked by runner loss; the cause is named (VM freeze and a wedged Simulator), not a flag stall.

## Toolbar lane (toolbar-throttle, arm `stage`): undecided
Run 40365940148 (commit message [ci:toolbar-throttle] [throttle:toolbar] [toolbar-plan:stage,stage,stage]). The new arm
`stage` (`?fw=morph.stage:on`, look change) was added to `packages/measure-webkit/src/throttle/toolbar.mjs` and its test at commit 8f2f726bf (the CI commit); those two files are outside this task's writes, so the branch tip does not carry them (follow-up for the lead: re-add them with the arm if the lane is run again). Of the jobs that
uploaded, the stage pass of job 3 ended `restartFailed` (Simulator not ready after 1295 s), so the stage arm has 0 usable
passes and the report (toolbar-cli.mjs report) has a verdict row for no flag. Read the three uploaded jobs: default arm only,
3 passes, 1 usable. Undecided; six sim jobs failed or were cancelled.

## Track length T and class (for the user's review)
T = 696 px at 1280x800 and 768 px at 390x844 (`trackT_ge`, `trackT_least` in MorphStage.lean: the least track that keeps the
morph start where the faithful tween starts). Class L: look change (the morph follows the finger, no 680 ms play). The user
reviews the end feel and chooses T; the flag is never in a preset.
