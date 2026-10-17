# Gaps lane: the 8 Q33 cells

Every state is Lean's (gate.state with the engine's port): `pass` / `fail` (environment reached, judged like every gate cell), `unreachable:<reason>` (the port cannot build the requested environment; the reason is the one proved in Fw.Gate.Reach) and `not-comparable`.

- chromium (port chromium): Chrome/156.0.8078.4
- playwright-webkit (port webkit-glib): WebKit 27.2 (playwright-core 1.64.1)

| cell | engine | state | reach | requested (Lean) | realized | page saw (orig / rewrite) |
|---|---|---|---|---|---|---|
| hover-pointer-cross-1024x768-none-fine | chromium | **pass** | - | 1024x768 dpr 2 none/fine | 1024x768 dpr 2 none/fine | pair none/fine / none/fine |
| hover-pointer-cross-1024x768-hover-coarse | chromium | **pass** | - | 1024x768 dpr 2 hover/coarse | 1024x768 dpr 2 hover/coarse | pair hover/coarse / hover/coarse |
| hover-pointer-cross-1200x900-none-fine | chromium | **pass** | - | 1200x900 dpr 2 none/fine | 1200x900 dpr 2 none/fine | pair none/fine / none/fine |
| hover-pointer-cross-1200x900-hover-coarse | chromium | **pass** | - | 1200x900 dpr 2 hover/coarse | 1200x900 dpr 2 hover/coarse | pair hover/coarse / hover/coarse |
| fractional-gaps-600.5 | chromium | **pass** | - | 600.5x900 dpr 2 hover/fine | 600.5x900 dpr 2 hover/fine, zoom 2, override 1201x1800 | media 600.5 / 600.5, vv 600.5, inner 600, dpr 2 |
| fractional-gaps-640.5 | chromium | **pass** | - | 640.5x900 dpr 2 hover/fine | 640.5x900 dpr 2 hover/fine, zoom 2, override 1281x1800 | media 640.5 / 640.5, vv 640.5, inner 640, dpr 2 |
| fractional-gaps-860.5 | chromium | **pass** | - | 860.5x900 dpr 2 hover/fine | 860.5x900 dpr 2 hover/fine, zoom 2, override 1721x1800 | media 860.5 / 860.5, vv 860.5, inner 860, dpr 2 |
| fractional-gaps-1000.5 | chromium | **pass** | - | 1000.5x900 dpr 2 hover/fine | 1000.5x900 dpr 2 hover/fine, zoom 2, override 2001x1800 | media 1000.5 / 1000.5, vv 1000.5, inner 1000, dpr 2 |
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
| chromium | hover-pointer-cross | pass | 0 | 4 | 0 |
| chromium | fractional-gaps | pass | 0 | 4 | 0 |
| playwright-webkit | hover-pointer-cross | unreachable:primary-pair | 0 | 0 | 4 |
| playwright-webkit | fractional-gaps | unreachable:whole-width | 0 | 0 | 4 |

## Does the reach model hold on what WebKit pages reported? (Lean: gate.reach, then the cell rule)

| mechanism | port | verdict | records | contradicted | unreadable |
|---|---|---|---|---|---|
| playwright-webkit/run fractional | webkit-glib | pass | 8 | 0 | 0 |
| playwright-webkit/run cross | webkit-glib | pass | 8 | 0 | 0 |
| playwright-webkit/dpr | webkit-glib | pass | 16 | 0 | 0 |
| playwright-webkit/pair | webkit-glib | pass | 4 | 0 | 0 |

## Simulator records through the phone-session rule (dry run of the device check)


## Not collected here (with the reason)

- apple: not collected on linux: the macOS and Simulator arms need an Apple host

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

macOS system WebKit (WKWebView pageZoom) (0 records)

| request | saw |
|---|---|

