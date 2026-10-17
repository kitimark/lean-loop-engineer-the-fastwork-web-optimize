# Phone session 1 (2026-10-17): the measurement iPhone

Device: the measurement iPhone (15 Pro Max), iOS 27.0.1 (build 24A446), Safari 27.0.1 (frozen UA reads iPhone OS 18_7),
viewport 430 x 775 css px, DPR 3, **Dark appearance** (the phone's setting; not changed). Harness: base `e5bf4e4` plus the
commit that adds `packages/measure-webkit/src/device*.mjs` and `packages/gate-breakpoints/src/gaps/device{cells,drive}.mjs`.
Both sites were served from the Mac to the phone over the LAN; the page is driven through the Web Inspector (iwdp) with a
proxy on its own ports. No address or device id is stored here. Everything below is MEASURED on the device unless marked.

Device time: about 20 min in three blocks (gap drive; counts 5 min; frames 6 min), each well under 15 min, cooled >= 5 min
between blocks. Readouts (battery %, charging, battery temperature) are in each file's `readouts`: battery 77 to 80 %,
battery temperature 32 C at every readout (no rise). The iOS thermal state is **not exposed** over USB or the inspector,
so battery temperature is the only heat proxy; charging was read as true during counts and false during frames.

## gap-device (Q33): 8 agree, 0 disagree (`gap-device/`)
All 8 cells (4 fractional widths 600.5 / 640.5 / 860.5 / 1000.5, 4 hover x pointer crosses) are unreachable in Lean
(`unreachable:whole-width`, `unreachable:primary-pair`), the phone did not realize any of them, and its facts equal the
Simulator's (CI run 39044573514). Verdict file checks: W, X, T pass; L pass; S ("equal to the Simulator") differs only in
`dark` (the phone is in Dark appearance; the Simulator is Light), so `device-verdict.json` has `pass:false` for that reason only.
The aA zoom, landscape and mouse steps of `DEVICE.md` need a hand and were not done.

## (a) WebKit counts, same profile as the Simulator lane (`counts-*.json`, `counts-compare.md`)
3 passes + 1 discarded warm-up per site, pinned clock, states 0/1500/3000/4500/max, zones of 500 px. Totals per scroll
(mean of passes; Simulator original = CI run 39048376821, 2 passes):

| count | phone original | Simulator original | phone rewrite |
|---|---|---|---|
| RecalculateStyles | 654 | 716 | 162 |
| Layout | 622 | 696 | 156 |
| Paint | 1575 | 1342 | 174 |
| Composite | 213 | 213 | 147 |
| FireAnimationFrame | 731 | 726 | 295 |
| TimerFire | 35 | 136 | 2 |
| EventDispatch | 107 | 107 | 148 |

Classes (Fw/Measure/Classes, policy kMax 4, tMax 24): original 34 deterministic / 13 stable / 25 quarantined; rewrite
37 / 12 / 9. Phone and Simulator agree exactly on Composite and EventDispatch and are within a few percent on
FireAnimationFrame; Style and Layout are 9 to 11 % lower on the phone, Paint 17 % higher, TimerFire a quarter of the
Simulator's. Zone-by-zone tables are in `counts-compare.md`. **The rewrite is a placeholder page** (document height
and layer count are far smaller), so original-versus-rewrite is not like-for-like and says nothing about a finished rewrite.

## (b) Frame timing under a scripted scroll (`frames-*.json`) -- SCRIPTED, not a finger swipe
requestAnimationFrame-driven `scrollTo` at 800 px/s, 2 rounds x 5 reps per site, alternating A R A R. Intervals between
moving frames; Safari timestamps have 1 ms resolution; a scripted scroll has no compositor momentum, so these numbers
are a lower-fidelity stand-in for a swipe.

| site | moving frames | > 34 ms per 100 | > 50 ms per 100 | longest |
|---|---|---|---|---|
| original | 2003 | 28.7 | 22.9 | 164 ms |
| rewrite (placeholder) | 2700 | 0.04 | 0 | 35 ms |

Original, by zone (y0 px): 0-2500 have 98 to 100 per 100 frames over 34 ms (median interval 72 to 90 ms, about 12 fps);
3000 has 48 per 100; from 3500 on 0 (median 17 ms). Rewrite: every zone median 17 ms, one frame of 2700 over 34 ms.
Per-round summaries are in the files; the two rounds agree (original 27.8 / 29.5, rewrite 0 / 0.07 per 100 over 34 ms).
