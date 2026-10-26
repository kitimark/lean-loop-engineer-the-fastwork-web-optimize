# platform-attribution: sweep and glint work is real but small and early, entries moves layouts only in the approach, marquee does nothing; WebKit entries and marquee are undecided (2 of 3 VMs)

* Answer (MEASURED, CI only). Premise (a) sweep holds on WebKit (finish Paint 166-222 down to 80-143) and holds in part on Chromium (215 fewer raster tasks and 792 fewer PaintImage over the finish window, but Paint +1 per frame, so the Lean verdict reads no-gain after the approach). Premise (b) glint holds only in the push approach and the first 20 end frames (Chromium 38 fewer raster tasks, 9 fewer style recalcs, nothing after end+20; WebKit z5000 Paint 54-66 down to 40-44, finish no-gain). Premise (c) entries is refuted for the end phases on Chromium (5 of 6 approach layouts gone, nothing after the end) and undecided on WebKit (n = 2 of 3 VMs). Marquee: no effect on Chromium; WebKit undecided (n = 2).
* Recommendation (INFERRED from the cells): build (a) the sweep variant that removes per-frame paint, first on WebKit where the finish saving is largest; build (b) glint only as an approach-bounded variant, expected gain small; do not build (c) entries until a 3-VM WebKit rerun exists; build nothing for marquee. Step-2 variants are built in later tasks.
* Probe arms are measurement-only flags (`platform.<part>:probe-off`, Lean `Kind.probe`, theorems `probe_not_mem`, `probe_not_mem_lookCandidates`, `probe_not_isOpt`; golden `packages/contracts/golden/preset/probes.jsonl`); they are never promoted into a preset or a look verdict. The sweep arm stops only its animation (`animation: none`, class and gradient kept) so it removes the animated work and nothing else.

## Runs (all at ci/platform-attribution; base = main-era base runs)
| engine | arm | run | VMs / runs |
|---|---|---|---|
| WebKit Simulator | base | 40203774734 (r2, r3), 40236531932 (r1 rerun, r2 extra) | 3 VMs, 6 passes |
| WebKit | sweep:probe-off | 40237513521 (86b876b) | 3 VMs, 6 passes |
| WebKit | glint:probe-off | 40236465002 (063b150) | 3 VMs, 6 passes |
| WebKit | entries:probe-off | 40236534457 (063b150) | 2 VMs (r1 job failed; lost VM r1, no rerun) |
| WebKit | marquee:probe-off | 40236475717 (063b150) | 2 VMs (r3 job failed; lost VM r3, no rerun) |
| Chromium swipe-touch-v1 | base | 40203753344 | 3 runs |
| Chromium | sweep / glint / entries / marquee | 40237508223 / 40236516819 / 40236472868 / 40236462082 | 3 runs each |
Superseded: the first sweep arm (runs 40236459376 Chromium, 40236443781 WebKit) removed the class and made Paint a counter artifact.

## Rule
* WebKit: Lean `Fw.Measure.OffscreenWebKit` (golden `packages/contracts/golden/measure/offscreen-webkit.jsonl`, replayed by `packages/measure-webkit/test/offscreen-webkit.test.mjs`). Base and arm are compared only on the same steps (`sameWindow` over equal step sets) with a common window y <= 5200 (the passes end at 5231 or 5267). Reader: `node packages/measure-webkit/src/offscreen-webkit-cli.mjs --arm base=<dirs> --arm name=<dirs>`. A cell with fewer than 3 VMs in an arm is reported undecided (n shown), never no-win.
* Chromium: the same Lean cmp/judge per window, 3 runs per arm, windows approach (34 frames), end 0-19 (20), end 20-59 (40), end 60-119 and 120+ (both shown as end 60+), finish (all 201).

## WebKit (MEASURED; counts summed per zone, min-max over passes; base 6 passes)
| zone (steps) | arm | passes | verdict | counts that differ | Paint base / arm |
|---|---|---|---|---|---|
| z4500 (10) | sweep | 6+6 | no-gain | none | 105-156 / 45-107 |
| z4500 | glint | 6+6 | no-gain | none | 105-156 / 130-143 |
| z4500 | entries | 6+4 | undecided (n=2 VMs) | would read: FireAnimationFrame less, ObserverCallback less | 105-156 / 89-142 |
| z4500 | marquee | 6+4 | undecided (n=2) | would read no-gain | 105-156 / 120-134 |
| z5000 (5) | sweep | 6+6 | gain | Paint less | 54-66 / 30-36 |
| z5000 | glint | 6+6 | gain | Paint, EventDispatch, FunctionCall less | 54-66 / 40-44 |
| z5000 | entries | 6+4 | undecided (n=2) | would read: ObserverCallback less | 54-66 / 40-56 |
| z5000 | marquee | 6+4 | undecided (n=2) | would read no-gain | 54-66 / 48-65 |
| finish (15) | sweep | 6+6 | gain | Paint less | 166-222 / 80-143 |
| finish | glint | 6+6 | no-gain | none | 166-222 / 174-186 |
| finish | entries | 6+4 | undecided (n=2) | would read: ObserverCallback less (14 to 6) | 166-222 / 141-197 |
| finish | marquee | 6+4 | undecided (n=2) | would read no-gain | 166-222 / 168-199 |
Layout, RecalculateStyles and Composite are inside the base spread for every arm (Composite 30 in finish for all). Full output: the CLI above on the downloaded `webkit-sim-r*` artifacts.

## Chromium (MEASURED; 3 runs per arm; windows in frames from the end)
| window | sweep | glint | entries | marquee |
|---|---|---|---|---|
| approach (34) | gain: RasterTask 236 to 61, PaintImage 137 to 1 | gain: RasterTask 236 to 200, recalcs 129 to 120, Layout 6 to 5 | no-gain: Layout 6 to 1, RasterTask 236 to 211, but FireAnimationFrame 120 to 122 (cost) | no-gain |
| end 0-19 | no-gain: RasterTask 517 to 477, Paint 335 to 352 (cost) | gain: RasterTask 517 to 515 | gain: Paint 335 to 330, RasterTask 517 to 512 | no-gain |
| end 20-59 | no-gain (Paint 252 to 292 cost) | no-gain | no-gain | no-gain |
| end 60+ | no-gain (Paint 120 to 180, PaintImage 240 to 0) | no-gain | no-gain | no-gain |
| finish (201) | no-gain: RasterTask 1207 to 992, PaintImage 1514 to 722, Paint 915 to 1079 (cost) | gain: RasterTask 1207 to 1169, recalcs 319 to 310 | no-gain: Layout 52 to 47, recalcs 319 to 310, FireAnimationFrame 400 to 402 (cost) | no-gain (recalc 319 to 320, cost) |
Sweep Paint +1 per frame is a counter artifact of `animation: none` (INFERRED: the paint of the static band is counted once per frame while the raster and PaintImage tasks vanish); the Lean verdict reads it as a cost, so the sweep Chromium cell is not a certified gain.

## Premises
* (a) sweep layer: holds on WebKit (z5000 and finish Paint down 40-50 percent, 3 VMs, run 40237513521 against base 40203774734 and 40236531932); holds on Chromium for raster work (run 40237508223 against 40203753344) but the Paint counter reads a cost.
* (b) glint transform: holds in the approach and end 0-19 on both engines (Chromium 40236516819, WebKit 40236465002); refuted for end 20+ on Chromium and for the WebKit finish zone.
* (c) entries contain: Chromium run 40236472868 removes 5 of 6 approach layouts (252 of 69851 layout objects) and nothing after the end, so the premise for end phases is refuted; WebKit run 40236534457 is undecided (2 of 3 VMs, VM r1 lost, no rerun).
