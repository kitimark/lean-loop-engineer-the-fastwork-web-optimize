---
id: 2026-10-20-fill-release-platform
kind: note
title: "fill-release-platform: filling backwards and writing the end values as style drops about 22 Chromium layers per frame after the platform entries end (tail layer-frames 7140 to 6480, -9.2%); work stays noGain (Paint less, RasterTask more)"
status: draft
created: 2026-10-20
topics: [chromium, webkit, animation-fill-mode, compositing, gpu-memory, platform.entries]
---

# Fill release for the platform entry animations

## Answer

- **Chromium memory: a win.** With `?fw=platform.entries:fill-release`, the census holds 216 layers per frame in the profile tail instead of 238. Tail layer-frames fall from 7140 to 6480 (-9.2%), drawing area falls by 7.7% and tiles fall by 10.9%. Base and flag come from the same run and commit (MEASURED, run 40280497740 at e133f74c8, 3 runs per arm, swipe-touch-v1).
- **Chromium work: noGain in every window.** The Lean windows reader finds Paint lower and RasterTask higher in approach, end 0-19 and finish. Windows end 20-59, 60-119 and 120+ show no difference (MEASURED, same run, `results/fill-release-platform/windows.md`).
- **Look: unchanged.** Lean `same_look` proves the shown value is the same at every time and in every `Env`, which includes every breakpoint width and both reduced-motion states (PROVED). `fill.test.ts` reads each of the 15 stylesheet rows back against the golden.
- **Breakpoint gate: pass on both engines.** Run 40282885162 at e133f74c8 with `?fw=platform.entries:fill-release`: Chromium 7056 readings, 7049 pass and 7 excused as not comparable; Playwright WebKit 7056 readings, 6765 pass and 291 excused (unreachable cells and a cell without a vector), no FAIL (MEASURED).
- **WebKit: no layer or memory change, work verdict undecided in all four zones (z4500, z5000, finish, whole) with n=1+3 VMs.** Simulator run 40282951274 (flag, 3 VMs) shows the same layer count and backing memory as the two good base VMs (40282962088 r2, 40305413688 r1) at every census stop (layers 141-145 at y 4500, 124-128 at the end; backing 149.3 MB and 105.8 MB; MEASURED). That matches `webkit_unchanged` (PROVED). The base run 40282962088 kept only VM r2 and the retry 40305413688 (same commit and inputs) kept only VM r1; r2 and r3 of the retry failed in their determinism sessions (host overload, task wk-sim-hang). Lean `minVms` is 3, so the reader (`offscreen-webkit-cli.mjs`) prints `undecided (n=1+3 VMs)` for every zone from the retry alone. The reader takes the VM id from the artifact dir name `r<k>` and Lean `vmCount` counts distinct ids with no commit field, so pooling works only when ids differ. Here they do (retry r1, first run r2) and give n=2+3 VMs, still below 3: undecided. The pooled pass rule alone reads noGain in every zone and is not a verdict. This is an accepted limit; the follow-up is a WebKit recount after wk-sim-hang lands.
- **Memory verdict: Chromium no-win, WebKit no-win (nothing to gain).** The memory budget is the existing `budgetB` (210 MiB, `Fw.Engine.Resource.budgetB_bytes`, `budgetB_quarter`). The flag only lowers memory, so `memoryWin_fits` holds at every budget with no measured peak. Chromium memory falls but RasterTask rises, so paint records are mixed and `work_change_not_memoryWin` rules out a memory-only win. WebKit memory and work do not change.

## Mechanism

- **Chromium.** An animation is in effect in the after phase when its fill is `forwards` or `both` (CONFIRMED, `third_party/blink/renderer/core/animation/timing_calculations.cc:103-130,141-161@f842f52`, `timing.cc:259,267-270`). CSS animations stay attached while they are current or in effect (CONFIRMED, `css/css_animations.cc:2225-2238,2267-2280@f842f52`). An element with such an animation on transform or opacity keeps its active-animation compositing reason, and therefore its own layer (CONFIRMED, `paint/compositing/compositing_reason_finder.cc:570-597@f842f52`). With `fill: backwards` the animation is not in effect after its end, so the reason goes away. The static rule then shows the same `to` values.
- **WebKit.** Only the active phase affects the property and keeps the accelerated animation (CONFIRMED, `Source/WebCore/animation/AnimationEffectTiming.cpp:182-201,219-241`, `KeyframeEffect.cpp:1703-1715,2085-2089`, `rendering/RenderLayerCompositor.cpp:3841-3866@862f17d`).
- **The work shift.** Each released element now paints into its parent's layer instead of its own. That trades composited quads for raster in the parent tiles. This fits the extra RasterTask together with less Paint (INFERRED from the counts; no trace of single tiles was taken).

## Lean

`lean/Fw/Engine/VisualTimed.lean`:

| Theorem | Statement |
|---|---|
| `both_held` | under fill `both`, Chromium holds the layer in every phase |
| `released_after_backwards` | under fill `backwards`, Chromium does not hold the layer in the after phase |
| `release_no_held_after` | after the end, a released track is not held |
| `release_held_before_end` | before the end, a released track is held |
| `release_shown` | a released track of a `both` track that settles shows the same value at every time |
| `release_saves` | the released track's held frames are those before the end, and never more than the `both` track's |
| `webkit_same_fill` | WebKit's hold does not depend on the fill |

`lean/Fw/Parts/PlatformEntries.lean`, section `FillRelease`:

| Theorem | Statement |
|---|---|
| `same_look_motion` | same shown value under no-preference |
| `same_look_reduce` | same shown value under reduce |
| `same_look` | the two above together, for every `Env` |
| `faithful_held` | the faithful track is held at every time |
| `no_held_after` | the variant track is not held after `delay + dur` |
| `held_saved` | the variant's held frames are at most the faithful's |
| `webkit_unchanged` | the variant does not change WebKit's hold |
| `rows_win` | every variant row has more classes than its strongest rival |
| `rows_dur` | every row has a positive duration |

Memory section `MemoryTrade` (same file):

| Theorem | Statement |
|---|---|
| `memoryWin_fits` | a footprint with every gated resource unchanged and GPU memory down fits any budget B without a measured peak |
| `memoryWin_neutral` | `Fw.Engine.Resource.verdict` calls such a footprint neutral (it never says win without a falling gated resource) |
| `work_change_not_memoryWin` | one gated resource that is not unchanged rules out a memory-only win |

The budget is `Fw.Engine.Resource.budgetB` (210 MiB, a quarter of the 840 MiB jetsam fallback); `win_mono_budget` shows raising B never turns a win into a non-win.

The golden is `packages/contracts/golden/parts/platform-entries-fill.jsonl`. It is written by `lean/Fw/Parts/PlatformEntriesFillGolden.lean` and checked by `lean/scripts/check.sh`.

## Runs

| Run | Kind | Commit | Arms | State |
|---|---|---|---|---|
| 40280497740 | chromium-counts, swipe-touch-v1, 3 runs | e133f74c8 | base `rewrite`, flag `platform.entries:fill-release` | success |
| 40280497901 | lean | e133f74c8 | none | success |
| 40282885162 | breakpoint-gate, both engines | e133f74c8 | `platform.entries:fill-release` | success, pass |
| 40282951274 | webkit-sim, 3 VMs | e133f74c8 | flag `platform.entries:fill-release` | success |
| 40282962088 | webkit-sim, 3 VMs | e133f74c8 | base `rewrite` | failed: VMs r1 and r3 hit the 2100 s determinism bound, r2 good |
| 40305413688 | webkit-sim, 3 VMs (retry of the base) | e133f74c8 | base `rewrite` | failed: r1 good, r2 and r3 lost in determinism sessions (host overload, wk-sim-hang) |

## WebKit per-zone verdict

Reader: `node packages/measure-webkit/src/offscreen-webkit-cli.mjs`, base from run 40305413688, flag from run 40282951274, Lean `minVms` 3 (MEASURED).

| Zone | Steps | Passes base+flag | VMs base+flag | Verdict |
|---|---|---|---|---|
| z4500 | 10 | 2+6 | 1+3 | undecided (n=1+3 VMs) |
| z5000 | 5 | 2+6 | 1+3 | undecided (n=1+3 VMs) |
| finish | 15 | 2+6 | 1+3 | undecided (n=1+3 VMs) |
| whole | 105 | 2+6 | 1+3 | undecided (n=1+3 VMs) |

Pooling the retry's r1 with the first base run's r2 gives 2+3 VMs: still undecided in every zone. Follow-up: a WebKit recount after wk-sim-hang lands.

## Chromium windows

The end frame is 574 in all six runs. The windows are taken from the end frame with slack 0. Numbers are base to flag, per the Lean reader.

| Window | Verdict | Less | More |
|---|---|---|---|
| approach | noGain | Paint 114 to 109 | RasterTask 236 to 270, PaintImage 137 to 147 |
| end 0-19 | noGain | Paint 336 to 312 | RasterTask 517 to 520 |
| end 20-59 | noGain | none | none |
| end 60-119 | noGain | none | none |
| end 120+ | noGain | none | none |
| finish | noGain | Paint 916 to 887 | RasterTask 1207 to 1244, PaintImage 1514 to 1524 |

## Layer-frames

Values are means over 3 runs, base to flag (MEASURED, `results/fill-release-platform/layer-frames.json`). The tail is the last 30 frames (771 frames, tail 741-771).

| Span | Layers | Drawing layers | Drawing area | Tiles |
|---|---|---|---|---|
| approach | 5445 to 5006 (-8.1%) | 5214 to 4775 (-8.4%) | -4.0% | 5716 to 5450 (-4.6%) |
| end 0-19 | 4508 to 4192 (-7.0%) | 4375 to 4059 (-7.2%) | -3.7% | 4688 to 4502 (-4.0%) |
| end 20-59 | 9607 to 8779 (-8.6%) | 9327 to 8499 (-8.9%) | -6.2% | 10526 to 9667 (-8.2%) |
| end 60-119 | 14280 to 12960 (-9.2%) | 13860 to 12540 (-9.5%) | -7.7% | 15480 to 13800 (-10.9%) |
| end 120+ | 11186 to 10152 (-9.2%) | 10857 to 9823 (-9.5%) | -7.7% | 12126 to 10810 (-10.9%) |
| finish | 45026 to 41089 (-8.7%) | 43633 to 39696 (-9.0%) | -6.4% | 48536 to 44229 (-8.9%) |
| tail | 7140 to 6480 (-9.2%) | 6930 to 6270 (-9.5%) | -7.7% | 7740 to 6900 (-10.9%) |
| whole | 125024 to 119450 (-4.5%) | 119046 to 113472 (-4.7%) | -3.3% | 141317 to 135853 (-3.9%) |

The base runs agree to within 2 layer-frames. One flag run differs from the other two by at most 0.5%.

## Limits

- The same look holds only where each variant rule wins the cascade. `rows_win` counts classes, and `fill.test.ts` checks the rows against the stylesheet.
- At the end, the release can repaint the element once into its parent layer. This is the INFERRED cause of the RasterTask rise.
- The layer-frame sums use `runWindows` and `sumRange` of `packages/measure-chromium/src/offscreen-windows.mjs`, which the Lean window golden checks (`sumRange_add`, `pushWindows_sum`); `results/fill-release-platform/layer-frames.mjs` only reads `counts.json` and prints JSON.
- The census gives no Chromium GPU bytes: Chromium memory is read as layers, drawing area and tiles. WebKit gives backing bytes (`memoryBytes`), which are equal in both arms.
- Preset promotion is left for later. The visual class is E, so no review by the user is needed.

## Lesson

To Chromium, a finished animation with fill `forwards` or `both` is still an animation, and it keeps its layer. Write the end values as static style and use fill `backwards` only.
