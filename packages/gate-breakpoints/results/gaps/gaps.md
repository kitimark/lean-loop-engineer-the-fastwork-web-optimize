# Gaps lane: the 8 Q33 cells

State per cell and engine: `pass` / `fail` (environment reached, judged like every gate cell), `unreachable` (no mechanism; measured evidence holds on every record), `not-comparable`.

- chromium: Chrome/155.0.8059.85
- playwright-webkit: WebKit 27.2 (playwright-core 1.64.1)

| cell | engine | state | mechanism | Lean expects | page saw (orig / rewrite) |
|---|---|---|---|---|---|
| hover-pointer-cross-1024x768-none-fine | chromium | **pass** | --blink-settings primaryHoverType/primaryPointerType (one browser per pair) | pair none/fine at 1024 | pair none/fine / none/fine |
| hover-pointer-cross-1024x768-none-fine | playwright-webkit | **unreachable** | none: every Apple WebKit derives primary hover and pointer from one platform constant (WebPageIOS.mm:4233-4246, WebPageMac.mm:762-780@862f17d); Playwright hasTouch flips both | pair none/fine at 1024 | pair none/coarse / none/coarse |
| hover-pointer-cross-1024x768-hover-coarse | chromium | **pass** | --blink-settings primaryHoverType/primaryPointerType (one browser per pair) | pair hover/coarse at 1024 | pair hover/coarse / hover/coarse |
| hover-pointer-cross-1024x768-hover-coarse | playwright-webkit | **unreachable** | none: every Apple WebKit derives primary hover and pointer from one platform constant (WebPageIOS.mm:4233-4246, WebPageMac.mm:762-780@862f17d); Playwright hasTouch flips both | pair hover/coarse at 1024 | pair hover/fine / hover/fine |
| hover-pointer-cross-1200x900-none-fine | chromium | **pass** | --blink-settings primaryHoverType/primaryPointerType (one browser per pair) | pair none/fine at 1200 | pair none/fine / none/fine |
| hover-pointer-cross-1200x900-none-fine | playwright-webkit | **unreachable** | none: every Apple WebKit derives primary hover and pointer from one platform constant (WebPageIOS.mm:4233-4246, WebPageMac.mm:762-780@862f17d); Playwright hasTouch flips both | pair none/fine at 1200 | pair none/coarse / none/coarse |
| hover-pointer-cross-1200x900-hover-coarse | chromium | **pass** | --blink-settings primaryHoverType/primaryPointerType (one browser per pair) | pair hover/coarse at 1200 | pair hover/coarse / hover/coarse |
| hover-pointer-cross-1200x900-hover-coarse | playwright-webkit | **unreachable** | none: every Apple WebKit derives primary hover and pointer from one platform constant (WebPageIOS.mm:4233-4246, WebPageMac.mm:762-780@862f17d); Playwright hasTouch flips both | pair hover/coarse at 1200 | pair hover/fine / hover/fine |
| fractional-gaps-600.5 | chromium | **pass** | Chromium browser zoom 200% (profile Preferences partition.default_zoom_level.x = log(2)/log(1.2)) + CDP setDeviceMetricsOverride width 2N+1, DSF 1 | media width 600.5; neither (width<=600) nor (width>=601) | media 600.5 / 600.5, vv 600.5, inner 600, dpr 2 |
| fractional-gaps-600.5 | playwright-webkit | **unreachable** | none: WebKit media width is an int (MediaQueryFeatures.cpp:716-728@862f17d); Playwright has no zoom, fractional DPR gives whole px | media width 600.5; neither (width<=600) nor (width>=601) | media 601 / 601, vv 601, inner 601, dpr 2 |
| fractional-gaps-640.5 | chromium | **pass** | Chromium browser zoom 200% (profile Preferences partition.default_zoom_level.x = log(2)/log(1.2)) + CDP setDeviceMetricsOverride width 2N+1, DSF 1 | media width 640.5; neither (width<=640) nor (width>=641) | media 640.5 / 640.5, vv 640.5, inner 640, dpr 2 |
| fractional-gaps-640.5 | playwright-webkit | **unreachable** | none: WebKit media width is an int (MediaQueryFeatures.cpp:716-728@862f17d); Playwright has no zoom, fractional DPR gives whole px | media width 640.5; neither (width<=640) nor (width>=641) | media 641 / 641, vv 641, inner 641, dpr 2 |
| fractional-gaps-860.5 | chromium | **pass** | Chromium browser zoom 200% (profile Preferences partition.default_zoom_level.x = log(2)/log(1.2)) + CDP setDeviceMetricsOverride width 2N+1, DSF 1 | media width 860.5; neither (width<=860) nor (width>=861) | media 860.5 / 860.5, vv 860.5, inner 860, dpr 2 |
| fractional-gaps-860.5 | playwright-webkit | **unreachable** | none: WebKit media width is an int (MediaQueryFeatures.cpp:716-728@862f17d); Playwright has no zoom, fractional DPR gives whole px | media width 860.5; neither (width<=860) nor (width>=861) | media 861 / 861, vv 861, inner 861, dpr 2 |
| fractional-gaps-1000.5 | chromium | **pass** | Chromium browser zoom 200% (profile Preferences partition.default_zoom_level.x = log(2)/log(1.2)) + CDP setDeviceMetricsOverride width 2N+1, DSF 1 | media width 1000.5; neither (width<=1000) nor (width>=1001) | media 1000.5 / 1000.5, vv 1000.5, inner 1000, dpr 2 |
| fractional-gaps-1000.5 | playwright-webkit | **unreachable** | none: WebKit media width is an int (MediaQueryFeatures.cpp:716-728@862f17d); Playwright has no zoom, fractional DPR gives whole px | media width 1000.5; neither (width<=1000) nor (width>=1001) | media 1001 / 1001, vv 1001, inner 1001, dpr 2 |

## Rows of each reached cell (as in the gate table; - = row does not apply)

| cell | engine | matchMedia orig=rewrite | matchMedia =Lean | matchMedia legacy text | engine.scroll | nav.hitTest | hero.countdown | hero.exit | gap (Lean gap_iff) |
|---|---|---|---|---|---|---|---|---|---|
| hover-pointer-cross-1024x768-none-fine | chromium | pass | pass | pass | pass | pass | pass | pass | - |
| hover-pointer-cross-1024x768-hover-coarse | chromium | pass | pass | pass | pass | pass | pass | pass | - |
| hover-pointer-cross-1200x900-none-fine | chromium | pass | pass | pass | pass | pass | pass | pass | - |
| hover-pointer-cross-1200x900-hover-coarse | chromium | pass | pass | pass | pass | pass | pass | pass | - |
| fractional-gaps-600.5 | chromium | pass | pass | pass | pass | pass | pass | pass | pass |
| fractional-gaps-640.5 | chromium | pass | pass | pass | pass | pass | pass | pass | pass |
| fractional-gaps-860.5 | chromium | pass | pass | pass | pass | pass | pass | pass | pass |
| fractional-gaps-1000.5 | chromium | pass | pass | pass | pass | pass | pass | pass | pass |

## Simulator records through the phone-session rule (dry run of the device check)

- ipad: PASS; ok W whole media width, no gap (2 records); ok X pointer facts equal the Simulator (2 records); ok S equal to the Simulator at the same width (0 records compared); ok L equal to Lean where a vector exists (0 compared, 2 without a vector)
- iphone: PASS; ok W whole media width, no gap (2 records); ok X pointer facts equal the Simulator (2 records); ok S equal to the Simulator at the same width (2 records compared); ok L equal to Lean where a vector exists (2 compared, 0 without a vector)

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
| {"pageZoom":1,"width":601} | media 601, vv 601, inner 601, screen 1512, dpr 2, pair hover/fine |
| {"pageZoom":2,"width":1201} | media 601, vv 600.5, inner 600, screen 1512, dpr 4, pair hover/fine |
| {"pageZoom":2,"width":1281} | media 641, vv 640.5, inner 640, screen 1512, dpr 4, pair hover/fine |
| {"pageZoom":2,"width":1721} | media 861, vv 860.5, inner 860, screen 1512, dpr 4, pair hover/fine |
| {"pageZoom":2,"width":2001} | media 1001, vv 1000.5, inner 1000, screen 1512, dpr 4, pair hover/fine |
| {"pageZoom":1.1,"width":661} | media 601, vv 600.90625, inner 600, screen 1512, dpr 2.200000047683716, pair hover/fine |
| {"pageZoom":1.1,"width":705} | media 641, vv 640.90625, inner 640, screen 1512, dpr 2.200000047683716, pair hover/fine |
| {"pageZoom":1.1,"width":947} | media 861, vv 860.90625, inner 860, screen 1512, dpr 2.200000047683716, pair hover/fine |
| {"pageZoom":1.1,"width":1101} | media 1001, vv 1000.90625, inner 1000, screen 1512, dpr 2.200000047683716, pair hover/fine |
| {"pageZoom":1.25,"width":751} | media 601, vv 600.796875, inner 600, screen 1512, dpr 2.5, pair hover/fine |
| {"pageZoom":0.9,"width":541} | media 601, vv 601.109375, inner 601, screen 1512, dpr 1.7999999523162842, pair hover/fine |

iOS Simulator ipad (2 records)

| request | saw |
|---|---|
| {"device":"ipad","load":0} | media 1032, vv 1032, inner 1032, screen 1032, dpr 2, pair none/coarse |
| {"device":"ipad","load":1} | media 1032, vv 1032, inner 1032, screen 1032, dpr 2, pair none/coarse |

iOS Simulator iphone (2 records)

| request | saw |
|---|---|
| {"device":"iphone","load":0} | media 430, vv 430, inner 430, screen 430, dpr 3, pair none/coarse |
| {"device":"iphone","load":1} | media 430, vv 430, inner 430, screen 430, dpr 3, pair none/coarse |

