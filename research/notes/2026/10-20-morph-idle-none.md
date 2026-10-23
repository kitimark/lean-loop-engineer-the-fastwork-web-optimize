# morph.columns:idle-none: no track animation while the scene rule pauses the panel

Task morph-idle-none (paint PC4). Flag `morph.columns:idle-none`. Lean: `lean/Fw/Parts/MorphIdleNone.lean`.

## Answer

- Win, same look. Chromium swipe-v1, 3 runs per arm: layer-frames 28107 -> 24667 (-3440, -12.2 %), drawing layers 24904 -> 21464 (-3440).
  The base equals the earlier base of task morph-layers (28107, run 39309334426). WebKit simulator census (one session, two passes):
  layerCount at y=3000 140/136 -> 124/128, at y=4500 145/141 -> 129/136, at y=5231 128/124 -> 112/116; backing memory at y=3000 101 -> 85 MB
  and at y=5231 106 -> 90 MB, both deterministic (MEASURED).
- The drop is larger than the 1910 layer-frames attributed to tracks and columns on the base (tracks 1146, cols 764): the other 1530
  came with them (INFERRED: boxes that overlapped the animated tracks, the veil and backdrop merging; not attributed).
- Not a look change: no visClass L proposal. The breakpoint gate passes on both engines.

## Mechanism

While `data-start-selling-scene='paused'` (morph at most 0.001) the original keeps every track animation, paused at its held time. A paused
animation still gives its track an animation compositing reason (MEASURED on the base: 3 tracks with ActiveTransformAnimation, note
10-20-morph-layers.md). The variant sets `animation-name: none` on the tracks (`data-fw-idle`, same rule as `data-fw-dormant`), so the tracks
and the layers that overlap them go.

## Same look (Lean, class E)

- Removing the animation without keeping its time restarts the phase on return: `restart_shifts` (clock 16 against 32 after run, pause, run).
- The variant keeps each animation's `currentTime` at the removal and sets it again on the return, in the MutationObserver callback, before
  paint. Lean models it as `varStep`: `varRun_clock` (the kept clock is the original's held clock, `origClock`, after any frames), `varRun_present`
  (the animation exists exactly when the scene rule does not pause).
- `idleNone_visSame`: for every environment (width band, touch, hover) and instant, with the moving boxes under the panel, the visible scene equals the
  original's. While paused the panel opacity is 0 (`scenePaused_imp_hiddenPause`), so the removed state paints nothing in either arm; after the
  return the variant shows `shownO`. It is `panel_visSame` of `Fw.Parts.HiddenPause` with the animation value `Option Rat`.
- Layer model (`tracks_layers_drop`): three direct-space track chunks with two column chunks over them give 5 layers, the same chunks without the
  direct reason 1. `layers_idle_eq`: chunks absorbed by the layer below leave all other layers unchanged. The mapping to Chromium is INFERRED.
- Premises (hypotheses): the observer callback runs before the frame's style pass; `getAnimations()` forces the pause style so the kept time is the
  original's held time; assigning `currentTime` to the returned CSS animation sets its hold before the first frame.

## WebKit morph-zone cost (MEASURED, runs 39903977820 base, 39903974246 flag; webkit-sim rewrite lag=true cost=on, two passes)

Morph zone = idle frames, then open, rest, close after a synthetic wheel push. Paint / Composite in microseconds per frame, layers from
LayerTree reads in the zone (pass 0 / pass 1).

| zone | Paint base | Paint flag | Composite base | Composite flag | layers base | layers flag |
|---|---|---|---|---|---|---|
| idle | 975 / 1043 | 1169 / 1228 | 15875 / 48705 | 55593 / 49749 | 128 / 128 | 112 / 112 |
| open | 4110 / 11437 | 4792 / 17211 | 110861 / 343364 | 238475 / 218334 | 209 / 209 | 205 / 205 |
| close | 2365 / 1967 | 4430 / 4945 | 117733 / 160058 | 289735 / 510848 | 209 / 209 | 205 / 205 |
| all frames | 1343 / 2932 | 2347 / 2769 | 38125 / 91019 | 120950 / 111708 | | |

- Layers: lower in every zone (idle 128 -> 112, -12.5 %, mean composited area 9.96 -> 8.9 Mpx; open and close 209 -> 205). Layer count is
  deterministic in both passes.
- Paint and Composite per frame: no win shown. The flag arm reads higher, but the runner's frame rate differed (frames in the zone: base 78 and
  36, flag 29 and 28) and one arm varies up to 3x between its own two passes (base idle composite 15875 vs 48705), so the sign of the delta is
  not resolvable from these two-pass runs. The follow-up below settles the method and the verdict.
- Why (INFERRED): the Lean model `tracks_layers_drop` counts layers only; it proves 5 layers -> 1 with the tracks not animated and says nothing
  about per-frame cost. Unsourced guess: WebKit composites the whole tree each frame that something animates (the tween), so cost follows the tree being redrawn,
  not the 16 layers freed at rest.
- Run 39903974246 shows failed: the Determinism sessions step hit its 35-minute timeout (2106 s, after two 120 s inspector retries) 4 s after the CLI wrote r1-lag.json and exited 0. align, merge and lag-report were skipped. The uploaded artifact holds both passes (cost ok, failed []).
- Reduction of the layer reads: scratch script over `webkit-sim-r1/r1-lag.json` (snaps are [zone, layers]).

## Per-frame Paint and Composite: the committed reducer and the verdict (task morph-idle-followups)

Reducer: `Fw.Measure.WkCost`, section "Morph zones: cost per frame of two arms"; JS twin `packages/measure-webkit/src/lag/morphcost.mjs`
(`pnpm --filter @fw/measure-webkit exec node src/lag/cli.mjs morph-verdict --original a.json,b.json --rewrite c.json,d.json`); goldens
`packages/contracts/golden/measure/wkcost.jsonl`, kinds `morphNorm`, `morphCells`, `morphOutcome` (`test/lag-morphcost.test.mjs`).

- Two views per cell (zone x Paint or Composite) and pass: raw = mean microseconds per frame; normalized = that mean over the mean per frame of
  calm scroll (`scroll-calm`) of the same pass, the same runner and the same minute. `normPF_scale`: a runner `k` times as slow leaves the
  normalized view unchanged; `rawPF_not_scale`: the raw view moves with the runner.
- A cell states a difference only when the per-pass ranges of the arms are separated (`WebKitLag.verdict`) in both views the same way
  (`cellVerdict_agree`); views that disagree, or one overlapping, give overlap (`cellVerdict_disagree`).
- Outcome over the 8 cells (4 zones x 2 metrics): win only if every cell is lower (`outcome_win`), loss only if every cell is higher
  (`outcome_loss`), mixed when both occur (`outcome_mixed`), otherwise overlap (`outcome_overlap`); win and loss never hold together.
- Result, MEASURED: the two-pass runs 39903977820 / 39903974246 give overlap in all 8 cells (`run_39903977820_overlap`). New runs 39915136431
  (base) and 39915146774 (`morph.columns:idle-none`), webkit-sim rewrite lag=true cost=only, 3 VMs x 2 passes = 6 passes per arm
  (`run_39915136431_overlap`: all 8 cells overlap; `run_39915136431_outcome`: overlap). Verdict: UNRESOLVED: neither a win nor a loss is
  shown on per-frame Paint and Composite; the flag's ranges reach higher in 7 of 8 cells, so a loss is not ruled out. Layers stay down (deterministic, idle 128 -> 112).
- Why it stays unresolved: the CI Simulator composites on the CPU, so Composite per frame is about the frame interval and the same idle page
  reads 21-41 ms (base) and 21-70 ms (flag) between passes; zone frame counts differ between passes (rest: base 27-56, flag 8-61), which moves
  the raw view; the normalization does not remove the pass-to-pass spread of the calm baseline (calm Composite 1.4-2.9 s per 86 frames).
  Ranges over the six passes, ms per frame (raw) / ratio to calm (norm):

| cell | base raw | flag raw | base norm | flag norm |
|---|---|---|---|---|
| Paint idle | 0.92-1.33 | 0.73-1.26 | 0.79-1.23 | 0.79-1.48 |
| Paint open | 3.46-9.08 | 5.65-20.25 | 3.17-8.50 | 7.45-19.09 |
| Paint rest | 1.05-4.58 | 0.95-18.44 | 0.90-3.76 | 1.16-20.15 |
| Paint close | 1.80-3.65 | 2.20-6.32 | 2.04-3.42 | 2.64-6.91 |
| Composite idle | 20.6-41.3 | 21.3-70.4 | 0.65-1.44 | 1.23-3.33 |
| Composite open | 120-224 | 110-1026 | 5.79-9.84 | 6.95-47.9 |
| Composite rest | 29.2-64.5 | 27.2-230 | 0.93-3.40 | 1.57-10.9 |
| Composite close | 103-197 | 106-309 | 3.27-11.2 | 5.96-14.6 |

- Accepted limit: the CI Simulator is not the phone. A phone arm (the real GPU compositor) is the way to resolve the sign; it is not part of this task.
- Item 4 (Chromium base 28107 layer-frames on the font image): not re-measured. counts-font-fidelity has not landed, so its
  image is not the one to measure on; the base-vs-flag delta (-3440) stays valid because both arms ran on one image. Closed by the section
  "Chromium re-baseline on the font image" below.

## Costs and limits

- Layout 318 -> 319 and style recalc 1832 -> 1833 over the run (MEASURED, +1 each; INFERRED: the forced style flush of `getAnimations()` at a
  pause or a return).
- Touch and WebKit attribution stay INFERRED (WebKit census is one session, layerCount spread 4-7 between passes; backing memory at y=3000
  and y=5231 is deterministic).
- counts-lane-fonts changed the Chromium image after these runs. No Chromium rerun was made; the 28107 base and the
  delta come from one image (both arms at 540130e9f); whether the base now differs is not measured.
- The glue is now checked: `IdleHold` (keep and restore of `currentTime`) runs the Lean model `Fw.Measure.IdleHold` golden (`wkcost.jsonl`, kind
  `idleHold`; `idle.hold.golden.test.ts`; theorems `restoreOne_hit`, `restoreOne_miss`, `keepOne_noTarget`, `keepOne_noTime`, `restore_twice`,
  `hold_returns_orig_clock` link the kept time to `origClock`). The scene threshold is checked in the attribute writer: `createPanelWriter(...).apply(mm / 1000)`
  writes `paused` exactly where `morph-idle-none.jsonl` says the removal holds (`morph.panel/scene.golden.test.ts`, `idle.golden.test.ts`).
  Still a TS stand-in: the MutationObserver wiring in `index.tsx`, and `IdleHold`'s `Map` keyed by element (the model keys by id).

## Runs (sha 540130e9f on ci/morph-idle-none)

| lane | base | flag |
|---|---|---|
| chromium-counts swipe-v1 x3 | 39897804079 | 39897818039 |
| webkit-sim | 39897814980 | 39897807511 |
| webkit-sim cost=on lag=true | 39903977820 | 39903974246 |
| webkit-sim cost=only lag=true, 3 VMs (morph-idle-followups, ci/morph-idle-followups) | 39915136431 | 39915146774 |
| breakpoint-gate both engines | | 39897800920 (merge job re-run once: ECONNRESET in download-artifact; all 7 shards succeeded) |

Numbers: `results/morph-idle-none/report.json`.

## Chromium re-baseline on the font image (task morph-idle-chromium-rebaseline)

Item 4 above is closed: counts-font-fidelity landed (fonts-liberation pinned), so the Chromium lane now lays out with fonts. Lane:
chromium-counts, swipe-v1, rewrite target, 3 VMs per arm. Unit: `census.layers` summed over the frames of zones rest..y05000 (545 frames: 10 +
49 + 9 x 50 + 36; the 30-frame tail zone is left out), one sum per VM shard, from the `zones.json` each CI shard stores (zone sums by fwcore
`measure.zoneSums`). Numbers: `results/morph-idle-none/chromium-font-rebaseline.json` (MEASURED).

Primary pair, one image id: both arms dispatched with `image_run=39914488176` (the frozen font image), so all six shards report image
`47b1dcbe`. Base run 39940682332 (no flag), flag run 39940686591 (`fw=morph.columns:idle-none`).

| shard | base | flag | delta | % |
|---|---|---|---|---|
| r1 | 74368 | 71036 | -3332 | -4.48 |
| r2 | 74365 | 71034 | -3331 | -4.48 |
| r3 | 74366 | 71037 | -3329 | -4.48 |
| font-less (earlier) | 28107 | 24667 | -3440 | -12.2 |

- Sign and size hold: the flag has fewer layer-frames in 3 of 3 shards, delta -3329 to -3332. The earlier separate-image pair gave -3331 / -3330 /
  -3325, so the two pairs agree within 7 layer-frames per shard (0.2 % of the delta).
- With the tail zone (575 frames) the delta is -3593, -3592, -3590. Drawing layers move by the same amount (-3330, -3331, -3330).
- The base is about 2.65 times the font-less base (74368 against 28107; the font-less figure was recorded over 503 frames, so per frame about 136
  against 56 layers). The relative win falls from -12.2 % to -4.5 %. The cause of the larger base stays INFERRED: the font-less lane laid the page
  out with fallback or missing text, so fewer boxes got layers; not measured here.
- Correction: the first version of this section called the rest..y05000 range 503 frames; the sums were right (they match the zone sums), the
  frame count is 545.

Supporting pair, separate images: base run 39936881473 (image a49c0675) and flag run 39937184249 (image 4782bc54), dispatched with `fw run`
(sha f3248e9, no `image_run`): base 74368 / 74365 / 74365, flag 71037 / 71035 / 71040, delta -3331 / -3330 / -3325 (-4.5 %). Base counts also agree
with the frozen font baseline run 39916914389 (74370 / 74367 / 74365), so the rebuilds count alike.

Chromium only. WebKit stays unresolved (see morph-idle-followups).
