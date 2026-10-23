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
  not resolvable from these runs. Verdict: layers down, per-frame Paint and Composite unresolved (a no-win on cost, not a loss).
- Why (INFERRED): the Lean model `tracks_layers_drop` counts layers only; it proves 5 layers -> 1 with the tracks not animated and says nothing
  about per-frame cost. WebKit composites the whole tree each frame that something animates (the tween), so cost follows the tree being redrawn,
  not the 16 layers freed at rest.
- Run 39903974246 shows failed: `error: forced exit: ... PipeWrap 2, Timeout 2` after `wrote r1-lag.json`; the artifact is complete.
- Reduction: scratch script over `webkit-sim-r1/r1-lag.json` (costs are [zone, paintUs, compUs]; snaps are [zone, layers]).

## Costs and limits

- Layout 318 -> 319 and style recalc 1832 -> 1833 over the run (MEASURED, +1 each; INFERRED: the forced style flush of `getAnimations()` at a
  pause or a return).
- Touch and WebKit attribution stay INFERRED (WebKit census is one session, layerCount spread 4-7 between passes; backing memory at y=3000
  and y=5231 is deterministic).
- counts-lane-fonts changed the Chromium image after these runs. No Chromium rerun was made; the 28107 base and the
  base-vs-flag delta come from one image (both arms at 540130e9f), so the delta stays valid; whether the base now differs is not measured.
- TS stand-in: the DOM glue (`IdleHold`, keep and restore of `currentTime`) is not checked against a golden; `idleRemoved` and `idleStep` equal `morph-idle-none.jsonl` (`idle.golden.test.ts`).

## Runs (sha 540130e9f on ci/morph-idle-none)

| lane | base | flag |
|---|---|---|
| chromium-counts swipe-v1 x3 | 39897804079 | 39897818039 |
| webkit-sim | 39897814980 | 39897807511 |
| webkit-sim cost=on lag=true | 39903977820 | 39903974246 |
| breakpoint-gate both engines | | 39897800920 (merge job re-run once: ECONNRESET in download-artifact; all 7 shards succeeded) |

Numbers: `results/morph-idle-none/report.json`.
