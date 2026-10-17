## chromium (Chrome/155.0.8059.85)

Rows: matchMedia of the 30 conditions + 4 neutral queries, original vs rewrite; against Lean's expected value (compared only where the env was achieved on both arms and a vector exists, else NC); the legacy max-/min- text against the range text; then the anchors of each part. Cells: pass / FAIL probes-failing/probes-comparable / NC = not comparable / - = block not run.

| row | desk | desk-rm | touch | touch-rm | phone-landscape | dw-arm-isolate | hover-pointer-cross | dark | fractional-gaps | height-probes | sweep:desktop-1512-320-1512 | sweep:phone-rotation | sweep:touch-1024-1201 | sweep:pain-1440-600-1440 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| env achieved | 30/30 | 30/30 | 30/30 | 10/10 | 2/2 | 6/6 | 4/4 | 2/2 | 0/4 | 6/6 |  |  |  |  |
| matchMedia orig=rewrite | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| matchMedia =Lean | pass | pass | pass | pass | pass | pass | pass | pass | NC | pass | pass | pass | pass | pass |
| matchMedia legacy text | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| engine.scroll | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC |
| nav.hitTest | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC |
| hero.countdown | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| hero.exit | FAIL 22/30 | FAIL 30/30 | FAIL 22/30 | FAIL 10/10 | FAIL 2/2 | FAIL 6/6 | FAIL 4/4 | FAIL 1/2 | FAIL 4/4 | FAIL 4/6 | FAIL 42/57 | FAIL 2/5 | FAIL 5/5 | FAIL 3/5 |

Sweep hysteresis (state after the sequence vs a fresh load at the same final env, per arm; items differing / compared):

- desktop-1512-320-1512: orig 0/1017, rewrite 0/1017
- phone-rotation: orig 0/1017, rewrite 0/1017
- touch-1024-1201: orig 0/1017, rewrite 0/1017
- pain-1440-600-1440: orig 0/1017, rewrite 0/1017

Failing items (count = probes or stops where the item differed; first example):

| part | kind | role | key | count | first at | orig | rewrite | lean |
|---|---|---|---|---|---|---|---|---|
| hero.exit | style | copy | left | 148 | desk-319 | "160px" | "159.5px" |  |
| hero.exit | style | copy | padding-left | 145 | desk-601 | "24px" | "0px" |  |
| hero.exit | style | copy | padding-right | 145 | desk-601 | "24px" | "0px" |  |
| hero.exit | style | copy | position | 145 | desk-601 | "relative" | "static" |  |
| hero.exit | style | copy | top | 145 | desk-601 | "0px" | "auto" |  |
| hero.exit | style | copy | filter | 31 | desk-rm-601 | "none" | "blur(0px)" |  |
| hero.exit | style | cue | filter | 10 | desk-rm-319 | "none" | "blur(0px)" |  |
| hero.exit | style | copy | transform | 3 | desk-319 | "matrix(1, 0, 0, 1, -160, 0)" | "matrix(1, 0, 0, 1, -159.5, 0)" |  |
| hero.exit | box | copy | w | 3 | desk-319 | 320 | 319 |  |
| hero.exit | style | cue | left | 3 | desk-319 | "160px" | "159.5px" |  |
| hero.exit | box | hero | w | 3 | desk-319 | 320 | 319 |  |
| hero.exit | box | track | w | 3 | desk-319 | 320 | 319 |  |

Properties only the original declares for a compared element (information, not in any verdict): 5 distinct (part, role, property); top 25:

| part | role | property | probes differing | first at | orig | rewrite |
|---|---|---|---|---|---|---|
| hero.exit | lead | font-family | 196 | desk-319 | "\"Google Sans\", -apple-system, \"system-ui\", \"Avenir Next\", Avenir, \"Segoe UI\", \"Helvetica Neue\", \"Adwaita Sans\", Cantarell, Ubuntu, Roboto, Noto, Helvetica, Arial, sans-serif" | "system-ui, -apple-system, \"Segoe UI\", sans-serif" |
| hero.exit | title | align-items | 196 | desk-319 | "center" | "normal" |
| hero.exit | title | display | 196 | desk-319 | "flex" | "block" |
| hero.exit | title | flex-direction | 196 | desk-319 | "column" | "row" |
| hero.exit | title | font-family | 196 | desk-319 | "\"Google Sans\", -apple-system, \"system-ui\", \"Avenir Next\", Avenir, \"Segoe UI\", \"Helvetica Neue\", \"Adwaita Sans\", Cantarell, Ubuntu, Roboto, Noto, Helvetica, Arial, sans-serif" | "system-ui, -apple-system, \"Segoe UI\", sans-serif" |

## playwright-webkit (WebKit 27.2 (playwright-core 1.64.1))

Rows: matchMedia of the 30 conditions + 4 neutral queries, original vs rewrite; against Lean's expected value (compared only where the env was achieved on both arms and a vector exists, else NC); the legacy max-/min- text against the range text; then the anchors of each part. Cells: pass / FAIL probes-failing/probes-comparable / NC = not comparable / - = block not run.

| row | desk | desk-rm | touch | touch-rm | phone-landscape | dw-arm-isolate | hover-pointer-cross | dark | fractional-gaps | height-probes | sweep:desktop-1512-320-1512 | sweep:phone-rotation | sweep:touch-1024-1201 | sweep:pain-1440-600-1440 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| env achieved | 30/30 | 30/30 | 30/30 | 10/10 | 2/2 | 6/6 | 0/4 | 2/2 | 0/4 | 6/6 |  |  |  |  |
| matchMedia orig=rewrite | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| matchMedia =Lean | pass | pass | pass | pass | pass | pass | NC | pass | NC | pass | pass | pass | pass | pass |
| matchMedia legacy text | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| engine.scroll | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC |
| nav.hitTest | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC |
| hero.countdown | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| hero.exit | FAIL 22/30 | FAIL 30/30 | FAIL 22/30 | FAIL 10/10 | FAIL 2/2 | FAIL 6/6 | FAIL 4/4 | FAIL 1/2 | FAIL 4/4 | FAIL 4/6 | FAIL 42/57 | FAIL 2/5 | FAIL 5/5 | FAIL 3/5 |

Sweep hysteresis (state after the sequence vs a fresh load at the same final env, per arm; items differing / compared):

- desktop-1512-320-1512: orig 0/1021, rewrite 0/1021
- phone-rotation: orig 0/1021, rewrite 0/1021
- touch-1024-1201: orig 0/1021, rewrite 0/1021
- pain-1440-600-1440: orig 0/1021, rewrite 0/1021

Failing items (count = probes or stops where the item differed; first example):

| part | kind | role | key | count | first at | orig | rewrite | lean |
|---|---|---|---|---|---|---|---|---|
| hero.exit | style | copy | left | 148 | desk-319 | "160px" | "159.5px" |  |
| hero.exit | style | copy | padding-left | 145 | desk-601 | "24px" | "0px" |  |
| hero.exit | style | copy | padding-right | 145 | desk-601 | "24px" | "0px" |  |
| hero.exit | style | copy | position | 145 | desk-601 | "relative" | "static" |  |
| hero.exit | style | copy | top | 145 | desk-601 | "0px" | "auto" |  |
| hero.exit | style | copy | filter | 31 | desk-rm-601 | "none" | "blur(0px)" |  |
| hero.exit | style | cue | filter | 10 | desk-rm-319 | "none" | "blur(0px)" |  |
| hero.exit | style | copy | transform | 3 | desk-319 | "matrix(1, 0, 0, 1, -160, 0)" | "matrix(1, 0, 0, 1, -159.5, 0)" |  |
| hero.exit | box | copy | w | 3 | desk-319 | 320 | 319 |  |
| hero.exit | style | cue | left | 3 | desk-319 | "160px" | "159.5px" |  |
| hero.exit | box | hero | w | 3 | desk-319 | 320 | 319 |  |
| hero.exit | box | track | w | 3 | desk-319 | 320 | 319 |  |

Properties only the original declares for a compared element (information, not in any verdict): 5 distinct (part, role, property); top 25:

| part | role | property | probes differing | first at | orig | rewrite |
|---|---|---|---|---|---|---|
| hero.exit | lead | font-family | 196 | desk-319 | "Google Sans, -apple-system, BlinkMacSystemFont, Avenir Next, Avenir, Segoe UI, Helvetica Neue, Adwaita Sans, Cantarell, Ubuntu, Roboto, Noto, Helvetica, Arial, sans-serif" | "system-ui, -apple-system, Segoe UI, sans-serif" |
| hero.exit | title | align-items | 196 | desk-319 | "center" | "normal" |
| hero.exit | title | display | 196 | desk-319 | "flex" | "block" |
| hero.exit | title | flex-direction | 196 | desk-319 | "column" | "row" |
| hero.exit | title | font-family | 196 | desk-319 | "Google Sans, -apple-system, BlinkMacSystemFont, Avenir Next, Avenir, Segoe UI, Helvetica Neue, Adwaita Sans, Cantarell, Ubuntu, Roboto, Noto, Helvetica, Arial, sans-serif" | "system-ui, -apple-system, Segoe UI, sans-serif" |

