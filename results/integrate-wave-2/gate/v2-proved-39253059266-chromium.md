## chromium (156.0.8078.4)

**Flags: ?preset=v2-proved - config 6762d15c2b8b6d35 (read from the loaded page).**

Rows: matchMedia of the 30 conditions + 4 neutral queries, original vs rewrite; against Lean's expected value (compared only where the env was achieved on both arms and a vector exists, else NC); the legacy max-/min- text against the range text; then the anchors of each part. Cells: pass / FAIL probes-failing/probes-comparable / NC = not comparable / UNREACHABLE n (reason) = every probe of the cell is a cell this engine port cannot build (Lean-proved reach rule), `+n unreachable` = n such probes left out of the count / - = block not run.

| row | desk | desk-rm | touch | touch-rm | phone-landscape | dw-arm-isolate | hover-pointer-cross | dark | fractional-gaps | height-probes | sweep:desktop-1512-320-1512 | sweep:phone-rotation | sweep:touch-1024-1201 | sweep:pain-1440-600-1440 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| env achieved | 30/30 | 30/30 | 30/30 | 10/10 | 2/2 | 6/6 | 4/4 | 2/2 | 0/4 | 6/6 |  |  |  |  |
| matchMedia orig=rewrite | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| matchMedia =Lean | pass | pass | pass | pass | pass | pass | pass | pass | NC | pass | pass | pass | pass +3 NC | pass |
| matchMedia legacy text | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| engine.scroll | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| nav.hitTest | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| morph.mount | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| hero.countdown | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| morph.countdown | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| hero.exit | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| morph.columns | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| morph.tween | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| morph.panel | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| nav | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| nav.langMenu | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| commission | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| commission.typing | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| overlays.drawer | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| overlays.signup | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| hero | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| hero.orbit | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| hero.deck | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| hero.accent | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| hero.cue | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| people.card | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| people.o | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| people.carousel | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| people.deck | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| pain | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| pain.notes | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| platform | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| platform.stageBg | FAIL 30/30 | FAIL 30/30 | FAIL 30/30 | FAIL 10/10 | FAIL 2/2 | FAIL 6/6 | FAIL 4/4 | FAIL 2/2 | FAIL 4/4 | FAIL 6/6 | pass | pass | pass | pass |
| platform.sweep | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| platform.glint | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| platform.entries | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| platform.marquee | FAIL 30/30 | FAIL 30/30 | FAIL 30/30 | FAIL 10/10 | FAIL 2/2 | FAIL 6/6 | FAIL 4/4 | FAIL 2/2 | FAIL 4/4 | FAIL 6/6 | pass | pass | pass | pass |
| engine.scene | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |

Settle wait (Lean Fw.Gate.Settle): 392 arm samples waited 195312 ms in total (max 1088 ms); 0 ended UNSETTLED. A state with an unsettled arm has no verdict (its rows are NC) and its items are not in the failing list.

Sweep hysteresis (state after the sequence vs a fresh load at the same final env, per arm; items differing / compared):

- desktop-1512-320-1512: orig 5/7394, rewrite 6/7394
- phone-rotation: orig 0/7646, rewrite 1/7646
- touch-1024-1201: orig 6/7394, rewrite 7/7394
- pain-1440-600-1440: orig 1/7394, rewrite 2/7394

Failing items (count = probes or stops where the item differed; first example):

| part | kind | role | key | count | first at | orig | rewrite | lean |
|---|---|---|---|---|---|---|---|---|
| platform.stageBg | style | artboard | will-change | 496 | desk-319 | "transform" | "auto" |  |
| platform.marquee | style | track | will-change | 124 | desk-319 | "transform" | "auto" |  |

Properties only the original declares for a compared element (information, not in any verdict): 1 distinct (part, role, property); top 25:

| part | role | property | probes differing | first at | orig | rewrite |
|---|---|---|---|---|---|---|
| hero | ctaButton | font-family | 196 | desk-319 | "\"Google Sans\", -apple-system, BlinkMacSystemFont, \"Avenir Next\", Avenir, \"Segoe UI\", \"Helvetica Neue\", \"Adwaita Sans\", Cantarell, Ubuntu, Roboto, Noto, Helvetica, Arial, sans-serif" | "Arial" |

