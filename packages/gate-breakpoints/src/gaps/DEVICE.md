# Phone session: the WebKit side of the Q33 gap cells (not run yet)

Goal: show on the real iPhone (iOS 27.0.1) what the Simulator (iOS 27.0) and the pinned WebKit source say: the media
`width` is always a whole number (so the four fractional cells cannot exist), and the primary `hover`/`pointer` pair is
always `(none, coarse)` (so the four cross cells cannot exist). Nothing here attaches the phone by itself: the Mac only
serves a page, and you open it in Safari.

## Steps (about 15 minutes)

1. On the Mac, same Wi-Fi as the phone:
   `cd packages/gate-breakpoints && node src/cli.mjs gaps device-serve --out out/device-a`
   It prints the Mac's address and the URL shape. The address is printed to the console only; do not commit it.
2. In Safari on the phone, open `http://<mac address>:8765/probe.html?tok=phone&label=load-1` in a new tab. The page shows
   its own JSON and POSTs one record on load, on every resize and when you tap "send".
3. Open the same URL again in another fresh tab with `label=load-2` (two loads, for the hover x pointer cells).
4. Fractional requests without the aA menu (the iOS rounding path; one fresh tab each, label as shown). The page sets its own
   meta viewport before the first layout:
   - content string: `...&label=vp-600.5&vp=width%3D600.5`, then `640.5`, `860.5`, `1000.5` the same way
   - aimed at a width on any phone: `...&label=aim-600.5&aim=600.5`, then `640.5`, `860.5`, `1000.5`
   The Simulator ran the same eight URLs (`evidence.json`, `simulator.*` records with `req.variant`).
5. Portrait, then landscape. In each: open the aA menu and step the page zoom through every level (50% to 300%, about 11
   levels; aA zoom is a second request path and is optional now that step 4 exists). After each step type the level into
   the label box (for example `portrait-125`) and tap "send".
6. Optional: Settings > Accessibility > larger text, one record (label `bigtext`). Optional: connect a Bluetooth mouse or
   trackpad, reload, label `mouse-1` (only `any-hover` and `any-pointer` may change).
7. Ctrl-C the server (it saves `out/device-a/device-records.json`), then judge against the Simulator records of the lane (the
   `evidence.json` of a CI `gaps-raw-macos-*` artifact):
   `node src/cli.mjs gaps device-judge --device out/device-a/device-records.json --sim <evidence.json> --out out/device-a`
   (needs fwcore: `FW_CORE_BIN=lean/.lake/build/bin/fwcore`.)

The same records can be read over Web Inspector instead of the POST path: the page keeps them in `window.__gapRecords`.

## Pass rule (devicejudge.mjs; the output lists every failing record)

| check | statement | what it proves |
|---|---|---|
| W | Lean's reach model (`gate.reach`, port `webkit-apple`) holds on every record: the media width is whole and the primary pair is `(hover, fine)` or `(none, coarse)` | the fractional and cross cells are unreachable on the device |
| X | every record without a `mouse` label: the 14 pointer facts other than `touchArm` equal the Simulator iPhone's; `mouse` records differ only in `any-hover` / `any-pointer` | the primary pair is `(none, coarse)` |
| T | `touchArm` of each record equals `(none, coarse) and vector.wLe1200` of Lean's vector at the record's own width (records without a vector are listed) | the width-dependent query follows the width; it is not compared with the Simulator's 430 px record |
| S | a record and a Simulator record with the same media width, screen width, hover and pointer: all 30 conditions and 4 neutral queries equal | the device answers what the Simulator answers |
| L | when the Lean matrix has a vector for the record's (width, device width, hover, pointer, reduced motion, scheme): all conditions equal Lean's | the device answers what Lean says; records without a vector are listed in `informative.withoutLeanVector` |

PASS = W and X and T and S and L, with at least one record. FAIL on any non-whole media width means WebKit's int rounding of
the 27.0 source no longer covers 27.0.1: the WebKit fractional cells become reachable on the device and are NC again. Any
difference in the primary pair reopens the four cross cells as NC. Informative only: a record whose `visualViewport.width`
is not whole (a fraction existed and was rounded).

If the phone is not 430 CSS px wide, S compares nothing and L has no vector at portrait 100%: W, X and T (where a vector
exists) still decide. Add the phone's width to the Lean matrix (a `touch` probe) to give L something to compare.
