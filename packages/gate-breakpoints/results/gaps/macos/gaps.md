# Gaps lane: the 8 Q33 cells

Every state is Lean's (gate.state with the engine's port): `pass` / `fail` (environment reached, judged like every gate cell), `unreachable:<reason>` (the port cannot build the requested environment; the reason is the one proved in Fw.Gate.Reach) and `not-comparable`.

- playwright-webkit (port webkit-apple): WebKit 27.2 (playwright-core 1.64.1)

| cell | engine | state | reach | requested (Lean) | realized | page saw (orig / rewrite) |
|---|---|---|---|---|---|---|
| hover-pointer-cross-1024x768-none-fine | playwright-webkit | **unreachable:primary-pair** | primary-pair | 1024x768 dpr 2 none/fine | 1024x768 dpr 2 none/fine | pair none/coarse / none/coarse |
| hover-pointer-cross-1024x768-hover-coarse | playwright-webkit | **unreachable:primary-pair** | primary-pair | 1024x768 dpr 2 hover/coarse | 1024x768 dpr 2 hover/coarse | pair hover/fine / hover/fine |
| hover-pointer-cross-1200x900-none-fine | playwright-webkit | **unreachable:primary-pair** | primary-pair | 1200x900 dpr 2 none/fine | 1200x900 dpr 2 none/fine | pair none/coarse / none/coarse |
| hover-pointer-cross-1200x900-hover-coarse | playwright-webkit | **unreachable:primary-pair** | primary-pair | 1200x900 dpr 2 hover/coarse | 1200x900 dpr 2 hover/coarse | pair hover/fine / hover/fine |
| fractional-gaps-600.5 | playwright-webkit | **unreachable:whole-width** | whole-width | 600.5x900 dpr 2 hover/fine | 600.5x900 dpr 2 hover/fine | media 601 / 601, vv 601, inner 601, dpr 2 |
| fractional-gaps-640.5 | playwright-webkit | **unreachable:whole-width** | whole-width | 640.5x900 dpr 2 hover/fine | 640.5x900 dpr 2 hover/fine | media 641 / 641, vv 641, inner 641, dpr 2 |
| fractional-gaps-860.5 | playwright-webkit | **unreachable:whole-width** | whole-width | 860.5x900 dpr 2 hover/fine | 860.5x900 dpr 2 hover/fine | media 861 / 861, vv 861, inner 861, dpr 2 |
| fractional-gaps-1000.5 | playwright-webkit | **unreachable:whole-width** | whole-width | 1000.5x900 dpr 2 hover/fine | 1000.5x900 dpr 2 hover/fine | media 1001 / 1001, vv 1001, inner 1001, dpr 2 |

## Blocks (Lean tally)

| engine | block | verdict | failing | total | unreachable |
|---|---|---|---|---|---|
| playwright-webkit | hover-pointer-cross | unreachable:primary-pair | 0 | 0 | 4 |
| playwright-webkit | fractional-gaps | unreachable:whole-width | 0 | 0 | 4 |

## Does the reach model hold on what WebKit pages reported? (Lean: gate.reach, then the cell rule)

| mechanism | port | verdict | records | contradicted | unreadable |
|---|---|---|---|---|---|
| playwright-webkit/run fractional | webkit-apple | pass | 8 | 0 | 0 |
| playwright-webkit/run cross | webkit-apple | pass | 8 | 0 | 0 |
| playwright-webkit/dpr | webkit-apple | pass | 16 | 0 | 0 |
| playwright-webkit/pair | webkit-apple | pass | 4 | 0 | 0 |
| macos-wkwebview/pageZoom | webkit-apple | pass | 11 | 0 | 0 |
| ios-simulator-safari ipad (plain loads) | webkit-apple | pass | 2 | 0 | 0 |
| ios-simulator-safari ipad (meta-viewport variants) | webkit-apple | pass | 8 | 0 | 0 |
| ios-simulator-safari iphone (plain loads) | webkit-apple | pass | 2 | 0 | 0 |
| ios-simulator-safari iphone (meta-viewport variants) | webkit-apple | pass | 8 | 0 | 0 |

## Informative: macOS WKWebView A=R row (pageZoom 2, window width 1201, never in a count)

Cell fractional-gaps-600.5 expectation, port left open. Verdict pass, environment achieved: false. Original: media 592, vv 592, inner 600, dpr 2. Rewrite: media 592, vv 592, inner 600, dpr 2.

Deviations from the request: {"orig":["width","height","reducedMotion"],"rewrite":["width","height","reducedMotion"]}

Rows: {"matchMedia orig=rewrite":"pass","matchMedia =Lean":"not-comparable","matchMedia legacy text":"pass"}

## Informative: Simulator meta-viewport variants (the iOS rounding path)

| device | variant | aimed | media width | vv width | inner width |
|---|---|---|---|---|---|
| ipad | vp-width-600.5 | 600.5 | 601 | 601 | 601 |
| ipad | vp-width-640.5 | 640.5 | 641 | 641 | 641 |
| ipad | vp-width-860.5 | 860.5 | 861 | 861 | 861 |
| ipad | vp-width-1000.5 | 1000.5 | 1001 | 1001 | 1001 |
| ipad | aim-600.5 | 600.5 | 1032 | 601 | 601 |
| ipad | aim-640.5 | 640.5 | 1032 | 641 | 641 |
| ipad | aim-860.5 | 860.5 | 1032 | 861 | 861 |
| ipad | aim-1000.5 | 1000.5 | 1032 | 1001 | 1001 |
| iphone | vp-width-600.5 | 600.5 | 601 | 601 | 601 |
| iphone | vp-width-640.5 | 640.5 | 641 | 641 | 641 |
| iphone | vp-width-860.5 | 860.5 | 861 | 861 | 861 |
| iphone | vp-width-1000.5 | 1000.5 | 1001 | 1001 | 1001 |
| iphone | aim-600.5 | 600.5 | 601 | 601 | 601 |
| iphone | aim-640.5 | 640.5 | 641 | 641 | 641 |
| iphone | aim-860.5 | 860.5 | 861 | 861 | 861 |
| iphone | aim-1000.5 | 1000.5 | 1001 | 1001 | 1001 |

## Simulator records through the phone-session rule (dry run of the device check)

- ipad: PASS; ok W Lean reach model holds (whole media width, primary pair) (2 records); ok X pointer facts equal the Simulator (2 records); ok T touchArm equals Lean at the record's own width (0 compared, 2 without a vector); ok S equal to the Simulator at the same width (0 records compared); ok L equal to Lean where a vector exists (0 compared, 2 without a vector)
- iphone: PASS; ok W Lean reach model holds (whole media width, primary pair) (2 records); ok X pointer facts equal the Simulator (2 records); ok T touchArm equals Lean at the record's own width (2 compared, 0 without a vector); ok S equal to the Simulator at the same width (2 records compared); ok L equal to Lean where a vector exists (2 compared, 0 without a vector)

## Evidence on the WebKit side

Playwright WebKit (20 records)

| request | saw |
|---|---|
| {"dpr":1,"hasTouch":false,"width":601} | media 601, vv 601, inner 601, screen 601, dpr 1, pair hover/fine |
| {"dpr":1.1,"hasTouch":false,"width":601} | media 601, vv 601, inner 601, screen 601, dpr 1.100000023841858, pair hover/fine |
| {"dpr":1.25,"hasTouch":false,"width":601} | media 601, vv 601, inner 601, screen 601, dpr 1.25, pair hover/fine |
| {"dpr":2,"hasTouch":false,"width":601} | media 601, vv 601, inner 601, screen 601, dpr 2, pair hover/fine |
| {"dpr":1,"hasTouch":false,"width":641} | media 641, vv 641, inner 641, screen 641, dpr 1, pair hover/fine |
| {"dpr":1.1,"hasTouch":false,"width":641} | media 641, vv 641, inner 641, screen 641, dpr 1.100000023841858, pair hover/fine |
| {"dpr":1.25,"hasTouch":false,"width":641} | media 641, vv 641, inner 641, screen 641, dpr 1.25, pair hover/fine |
| {"dpr":2,"hasTouch":false,"width":641} | media 641, vv 641, inner 641, screen 641, dpr 2, pair hover/fine |
| {"dpr":1,"hasTouch":false,"width":861} | media 861, vv 861, inner 861, screen 861, dpr 1, pair hover/fine |
| {"dpr":1.1,"hasTouch":false,"width":861} | media 861, vv 861, inner 861, screen 861, dpr 1.100000023841858, pair hover/fine |
| {"dpr":1.25,"hasTouch":false,"width":861} | media 861, vv 861, inner 861, screen 861, dpr 1.25, pair hover/fine |
| {"dpr":2,"hasTouch":false,"width":861} | media 861, vv 861, inner 861, screen 861, dpr 2, pair hover/fine |
| {"dpr":1,"hasTouch":false,"width":1001} | media 1001, vv 1001, inner 1001, screen 1001, dpr 1, pair hover/fine |
| {"dpr":1.1,"hasTouch":false,"width":1001} | media 1001, vv 1001, inner 1001, screen 1001, dpr 1.100000023841858, pair hover/fine |
| {"dpr":1.25,"hasTouch":false,"width":1001} | media 1001, vv 1001, inner 1001, screen 1001, dpr 1.25, pair hover/fine |
| {"dpr":2,"hasTouch":false,"width":1001} | media 1001, vv 1001, inner 1001, screen 1001, dpr 2, pair hover/fine |
| {"hasTouch":false,"hover":"hover","pointer":"fine"} | media 1024, vv 1024, inner 1024, screen 1024, dpr 2, pair hover/fine |
| {"hasTouch":true,"hover":"none","pointer":"fine"} | media 1024, vv 1024, inner 1024, screen 1024, dpr 2, pair none/coarse |
| {"hasTouch":false,"hover":"hover","pointer":"coarse"} | media 1024, vv 1024, inner 1024, screen 1024, dpr 2, pair hover/fine |
| {"hasTouch":true,"hover":"none","pointer":"coarse"} | media 1024, vv 1024, inner 1024, screen 1024, dpr 2, pair none/coarse |

macOS system WebKit (WKWebView pageZoom) (11 records)

| request | saw |
|---|---|
| {"pageZoom":1,"width":601} | media 601, vv 601, inner 601, screen 1024, dpr 1, pair hover/fine |
| {"pageZoom":2,"width":1201} | media 601, vv 600.5, inner 600, screen 1024, dpr 2, pair hover/fine |
| {"pageZoom":2,"width":1281} | media 641, vv 640.5, inner 640, screen 1024, dpr 2, pair hover/fine |
| {"pageZoom":2,"width":1721} | media 861, vv 860.5, inner 860, screen 1024, dpr 2, pair hover/fine |
| {"pageZoom":2,"width":2001} | media 1001, vv 1000.5, inner 1000, screen 1024, dpr 2, pair hover/fine |
| {"pageZoom":1.1,"width":661} | media 601, vv 600.90625, inner 600, screen 1024, dpr 1.100000023841858, pair hover/fine |
| {"pageZoom":1.1,"width":705} | media 641, vv 640.90625, inner 640, screen 1024, dpr 1.100000023841858, pair hover/fine |
| {"pageZoom":1.1,"width":947} | media 861, vv 860.90625, inner 860, screen 1024, dpr 1.100000023841858, pair hover/fine |
| {"pageZoom":1.1,"width":1101} | media 1001, vv 1000.90625, inner 1000, screen 1024, dpr 1.100000023841858, pair hover/fine |
| {"pageZoom":1.25,"width":751} | media 601, vv 600.796875, inner 600, screen 1024, dpr 1.25, pair hover/fine |
| {"pageZoom":0.9,"width":541} | media 601, vv 601.109375, inner 601, screen 1024, dpr 0.8999999761581421, pair hover/fine |

iOS Simulator ipad (10 records)

| request | saw |
|---|---|
| {"device":"ipad","load":0} | media 1032, vv 1032, inner 1032, screen 1032, dpr 2, pair none/coarse |
| {"device":"ipad","load":1} | media 1032, vv 1032, inner 1032, screen 1032, dpr 2, pair none/coarse |
| {"aimed":600.5,"device":"ipad","variant":"vp-width-600.5"} | media 601, vv 601, inner 601, screen 1032, dpr 2, pair none/coarse |
| {"aimed":640.5,"device":"ipad","variant":"vp-width-640.5"} | media 641, vv 641, inner 641, screen 1032, dpr 2, pair none/coarse |
| {"aimed":860.5,"device":"ipad","variant":"vp-width-860.5"} | media 861, vv 861, inner 861, screen 1032, dpr 2, pair none/coarse |
| {"aimed":1000.5,"device":"ipad","variant":"vp-width-1000.5"} | media 1001, vv 1001, inner 1001, screen 1032, dpr 2, pair none/coarse |
| {"aimed":600.5,"device":"ipad","variant":"aim-600.5"} | media 1032, vv 601, inner 601, screen 1032, dpr 2, pair none/coarse |
| {"aimed":640.5,"device":"ipad","variant":"aim-640.5"} | media 1032, vv 641, inner 641, screen 1032, dpr 2, pair none/coarse |
| {"aimed":860.5,"device":"ipad","variant":"aim-860.5"} | media 1032, vv 861, inner 861, screen 1032, dpr 2, pair none/coarse |
| {"aimed":1000.5,"device":"ipad","variant":"aim-1000.5"} | media 1032, vv 1001, inner 1001, screen 1032, dpr 2, pair none/coarse |

iOS Simulator iphone (10 records)

| request | saw |
|---|---|
| {"device":"iphone","load":0} | media 430, vv 430, inner 430, screen 430, dpr 3, pair none/coarse |
| {"device":"iphone","load":1} | media 430, vv 430, inner 430, screen 430, dpr 3, pair none/coarse |
| {"aimed":600.5,"device":"iphone","variant":"vp-width-600.5"} | media 601, vv 601, inner 601, screen 430, dpr 3, pair none/coarse |
| {"aimed":640.5,"device":"iphone","variant":"vp-width-640.5"} | media 641, vv 641, inner 641, screen 430, dpr 3, pair none/coarse |
| {"aimed":860.5,"device":"iphone","variant":"vp-width-860.5"} | media 861, vv 861, inner 861, screen 430, dpr 3, pair none/coarse |
| {"aimed":1000.5,"device":"iphone","variant":"vp-width-1000.5"} | media 1001, vv 1001, inner 1001, screen 430, dpr 3, pair none/coarse |
| {"aimed":600.5,"device":"iphone","variant":"aim-600.5"} | media 601, vv 601, inner 601, screen 430, dpr 3, pair none/coarse |
| {"aimed":640.5,"device":"iphone","variant":"aim-640.5"} | media 641, vv 641, inner 641, screen 430, dpr 3, pair none/coarse |
| {"aimed":860.5,"device":"iphone","variant":"aim-860.5"} | media 861, vv 861, inner 861, screen 430, dpr 3, pair none/coarse |
| {"aimed":1000.5,"device":"iphone","variant":"aim-1000.5"} | media 1001, vv 1001, inner 1001, screen 430, dpr 3, pair none/coarse |

