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
4. Portrait, then landscape. In each: open the aA menu and step the page zoom through every level (50% to 300%, about 11
   levels). After each step type the level into the label box (for example `portrait-125`) and tap "send".
5. Optional: Settings > Accessibility > larger text, one record (label `bigtext`). Optional: connect a Bluetooth mouse or
   trackpad, reload, label `mouse-1` (only `any-hover` and `any-pointer` may change).
6. Ctrl-C the server (it saves `out/device-a/device-records.json`), then judge against the Simulator records of the lane:
   `node src/cli.mjs gaps device-judge --device out/device-a/device-records.json --sim out/gaps-a/evidence.json --out out/device-a`
   (`out/gaps-a/evidence.json` comes from `node src/cli.mjs gaps run --out out/gaps-a`, which needs the sim-lock.)

The same records can be read over Web Inspector instead of the POST path: the page keeps them in `window.__gapRecords`.

## Pass rule (devicejudge.mjs; the output lists every failing record)

| check | statement | what it proves |
|---|---|---|
| W | every record: the media width is a whole number, and for each edge N one of `(width<=N)`, `(width>=N+1)` matches | the fractional cells are unreachable on the device (Lean `no_gap_ofNat`) |
| X | every record without a `mouse` label: all 15 pointer facts equal the Simulator iPhone's; `mouse` records differ only in `any-hover` / `any-pointer` | the cross cells are unreachable on the device: primary pair is `(none, coarse)` |
| S | a record and a Simulator record with the same media width, screen width, hover and pointer: all 30 conditions and 4 neutral queries equal | the device answers what the Simulator answers |
| L | when the Lean matrix has a vector for the record's (width, device width, hover, pointer, reduced motion, scheme): all conditions equal Lean's | the device answers what Lean says; records without a vector are listed in `informative.withoutLeanVector` |

PASS = W and X and S and L, with at least one record. FAIL on any non-whole media width means WebKit's int rounding of the
27.0 source no longer covers 27.0.1: the WebKit fractional cells become reachable on the device and are NC again. Any
difference in the primary pair reopens the four cross cells as NC. Informative only: a record whose `visualViewport.width`
is not whole (a fraction existed and was rounded).

If the phone is not 430 CSS px wide, S compares nothing and L has no vector at portrait 100%: W and X still decide. Add
the phone's width to the Lean matrix (a `touch` probe) to give L something to compare.
