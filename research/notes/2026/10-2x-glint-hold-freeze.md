# platform.glint:hold-freeze

Rank 2 of research/notes/2026/10-26-end-of-page-variants.md. Status: built and proved; look class E, gate pass both engines, Chromium counts read; WebKit cells undecided (n=2+3 VMs).

## What the flag does
The two repeating 5 s `<animate>` per glint dash (x1, x2 over six key times) become a ring of five pieces per attribute,
one per key-time segment, each with `fill="freeze"` and a `begin` equal to the end of the piece before it (segment 0 also
begins at `indefinite`). A segment where the value moves is an `<animate from to>` ramp, a segment where it holds is a
`<set>`. Per side three of five segments hold both attributes (left [1,2,4], right [0,3,4]); only there is no
non-`<set>` animation active. The two segment-0 pieces get `beginElement()` where the faithful arm calls it on its pair.
Before that, and after the dash unmounts, the static attributes (the rest values) apply, as in the original.

## Lean (lean/Fw/Parts/PlatformGlintHold.lean, no sorry)
- `hold_premise`, `hold_same_segments`: which segments hold, decided over X1 and X2.
- `hold_eq_faithful`: the hold sample equals the original at every elapsed time (class E).
- `active_unique`, `active_exists`, `active_seg`, `active_latest`: exactly one ramp or set piece per attribute is active.
- `ticking_hold` (0 against 2 while holding), `ticking_ramp`, `ticking_le` (never more than the original): the work claim.
- Golden packages/contracts/golden/parts/platform-glint-hold.jsonl (107 lines), replayed by
  apps/site/src/parts/platform.glint/hold.test.ts (sample, ticking, plan, const, and the pause and resume-seek runs).

## One SMIL clock writer
The flag adds no writer. The clock is paused and seeked only by `createPause` (platform.glint/pause.ts), reached from
`platform:faded-pause` (platform/index.tsx) or `platform.glint:offscreen-pause`, which already conflict. The golden `run`
lines drive `createPause` against a model of the SVG container and read the hold pieces at the frames after each event:
they equal the Lean values, so `pauseAnimations` and the resume seek keep hold-freeze equal to the original.
INFERRED (not run): that each engine re-evaluates the begin chain correctly after `setCurrentTime`; the look premise
on both engines is the check.

## Engine tick rules (CONFIRMED, code path shown)
- WebKit Source/WebCore/svg/animation/SVGSMILElement.cpp:1074-1088@862f17d `calculateNextProgressTime`: for an active
  element whose duration is indefinite or that is a `<set>`, the next progress time is the interval end (or the
  repeating-duration end); otherwise `elapsed + m_timeContainer->animationFrameDelay()`, every frame.
- Chromium third_party/blink/renderer/core/svg/animation/svg_smil_element.cc:1285-1301@f842f52 `NextProgressTime`: the
  same split, `interval_.end` for indefinite duration or `SVGSetElement`, `presentation_time` (next frame) otherwise.
- Not shown by these lines: the cost of a frame the container still runs for another element. That stays INFERRED; the
  counts decide.

## Results (CI only, no phone pass; runs on ci/glint-hold-freeze at a5e170b94, WebKit at cf69a9052)

### Look premise glint.hold-pixels: class E (MEASURED, run 40345059212)
Page packages/premise-tests/pages/glint.hold-pixels.html, test prem.glint.hold-pixels, Lean registry entry (theorem
`PlatformGlintHold.hold_eq_faithful`). Four strips (left and right dash, original pair against the ring), a paused SVG
timeline, `beginElement` at 10 s, then 30 judged times that never decrease: every key-time boundary of the first 5 s cycle
(a sample either side of 1, 2, 3, 4, 5) and the later boundaries 6, 10, 11, 12, 15, 16 and 20, every third one reached by unpause, `setCurrentTime`, pause in one task (what `createPause`
does on a reveal). Bound 12 of 255 per channel, and the colour band must be drawn.

| engine | browser | worst channel diff | samples |
|---|---|---|---|
| Chromium | Chrome Headless Shell 156.0.8078.4 | 1 | 30 judged + 2 backward |
| WebKit | Playwright WebKit 27.2 (Linux) | 0 | 30 judged + 2 backward |

Two findings of the premise work. (1) Ring ids that carry a hyphen (`secure-network-dash-left-X1S0`, what the flag first
used) leave every piece after the first unresolved in both engines: the dash never moved after segment 0. Ids are now letters
and digits (`fwglintleftX1S0`); hold.test.ts asserts it. (2) A backward `setCurrentTime` into segment 0 after the first cycle
shows the previous value in Chromium (diff 235, both locally and on CI) and is right in WebKit. No flag path seeks backward:
`createPause` seeks to the read time plus the paused time, so the container clock only moves forward; the two backward samples
are recorded as `backWorst` and not judged. The page restates the stops and key values (it does not import logic.ts), so the
flag's own React markup is not run in a browser for the look; the gate checks only the dash box (it excludes the SMIL x1/x2 values), and hold.test.ts checks the holdElements descriptors.

### Breakpoint gate: pass on both engines (run 40345141093, `?fw=platform.glint:hold-freeze`)
Chromium 156.0.8078.4: 124 probes, 4604 pass, 4 not comparable, 0 failing items, 0 unsettled. Playwright WebKit 27.2: 124 probes,
4320 pass, 288 unreachable (primary-pair 144, whole-width 144), 0 failing items, 0 unsettled. No flag delta excused.

### Chromium base against flag (swipe-touch-v1, 3 runs each, MEASURED)
Base `rewrite` run 40345261186, flag run 40345253392, same commit, read with `packages/measure-chromium/src/offscreen-windows-cli.mjs`
(Lean window functions, slack 0, end frame 574).

| window | verdict | less |
|---|---|---|
| approach | gain | RasterTask 236 to 225 |
| end 0-19 | noGain | none |
| end 20-59 | noGain | none |
| end 60-119 | noGain | none |
| end 120+ | noGain | none |
| finish | gain | RasterTask 1207 to 1196 |

The gain is one counter, RasterTask: about 5 percent in approach (236 to 225) and under 1 percent in finish (1207 to 1196); no counter more. The hold segments are not what the touch
profile spends its end windows on, so the window verdict there is no change.

### WebKit z5000
Simulator runs at cf69a9052 (3 VMs requested each): flag run 40349914211 (r1 lost to a `simctl bootstatus` abort, exit 134, re-run once; 3 of 3 VMs good on attempt 2),
base run 40349930733 (r2 lost twice: exit 1, then exit 130 on the re-run; r1 and r3 good, so 2 VMs). Reader: `node packages/measure-webkit/src/offscreen-webkit-cli.mjs`,
Lean `minVms` 3 (MEASURED). Every zone is undecided with n=2+3 VMs; the pass rule alone (not a verdict) reads z5000 as gain (Paint less, InvalidateLayout less).

| zone | steps | passes base+flag | VMs base+flag | verdict | Paint base / flag | Layout base / flag |
|---|---|---|---|---|---|---|
| z4500 | 10 | 4+6 | 2+3 | undecided (n=2+3 VMs) | 140-156 / 100-164 | 53-74 / 35-79 |
| z5000 | 5 | 4+6 | 2+3 | undecided (n=2+3 VMs) | 63-65 / 53-62 | 25-31 / 19-31 |
| finish | 15 | 4+6 | 2+3 | undecided (n=2+3 VMs) | 203-220 / 162-218 | 80-100 / 54-106 |
| whole | 105 | 4+6 | 2+3 | undecided (n=2+3 VMs) | 1245-1332 / 1121-1328 | 614-649 / 587-675 |

FireAnimationFrame is 22 in base z5000 against 22-26 in the flag, so the ring does not reduce animation-frame callbacks there. A third
good base VM decides the cells; the command is `gh run rerun 40349930733 --failed` (a re-run of r2) and then the reader above.

### Engine tick rules
Unchanged from the section above: the citations are CONFIRMED, the per-frame cost of a frame the container still runs stays INFERRED
and is what the counts above test.
