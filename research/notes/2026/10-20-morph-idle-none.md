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

## Costs and limits

- Layout 318 -> 319 and style recalc 1832 -> 1833 over the run (MEASURED, +1 each; INFERRED: the forced style flush of `getAnimations()` at a
  pause or a return).
- Touch and WebKit attribution stay INFERRED (WebKit census is one session, layerCount spread 4-7 between passes; backing memory at y=3000
  and y=5231 is deterministic). WebKit cost counters (`cost=on`, `lag=true`) were not collected: `fw run` sends no such input.
  Dispatch for the lead: `gh workflow run webkit-sim.yml --ref ci/morph-idle-none -f target=rewrite -f lag=true -f cost=on -f fw=morph.columns:idle-none`
  and the same without `-f fw=...`.
- TS stand-in: `IdleHold` (DOM glue) has no golden; `idleRemoved` and `idleStep` equal the Lean golden `morph-idle-none.jsonl`.

## Runs (sha 540130e9f on ci/morph-idle-none)

| lane | base | flag |
|---|---|---|
| chromium-counts swipe-v1 x3 | 39897804079 | 39897818039 |
| webkit-sim | 39897814980 | 39897807511 |
| breakpoint-gate both engines | | 39897800920 (merge job re-run once: ECONNRESET in download-artifact; all 7 shards succeeded) |

Numbers: `results/morph-idle-none/report.json`.
