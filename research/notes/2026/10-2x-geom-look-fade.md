# geom-look-fade: the pixel look judges the morph.geom flip

Task geom-look-fade (graph r546). Follows geom-page-diff (note 10-2x-geom-page-diff.md): the whole-page m=1 difference of morph.geom:on was a harness asymmetry on the platform section. This task fixes the harness and re-measures. No site code changed.

## What changed in the harness (packages/premise-tests/src/look.mjs)

| point | now |
|---|---|
| platform fade on base | `--morph-fade` and the pointer-events rule are written on the base arm from the Lean-generated constants (golden `look*` lines in packages/contracts/golden/morph-geom.jsonl); the driver writes the same two values, the pin bypassed them |
| scrollY | read on both arms, asserted equal (Lean `scrollEq`) |
| m of every track | the flip arm's `data-mg` WAAPI tracks are read back: grid tracks must show currentTime = m x duration, time tracks `ease(t/680)`, count and platform opacity checked (Lean `trackAt`, `tracksOk`, `fadeShows`); one `verify` object per row, `fails` named |
| look/timed | dropped as a pinned comparison: geom-timed has no MutationObserver, so a pinned m starts no flip and the old rows compared two unflipped pages. It now starts a real tween: m=1 is a real wheel tween (up to 8 tries, wait for `is-flip`, settle), m=0 is the untouched page; m=0.25/.5/.75 are skipped with a reason (Lean `timedSettled`: the timed page rests only at 0 and 1). Chromium only, see below |
| artifacts | per-region PNGs of both arms plus a diff image in `out/look/<on\|timed>/img/<band>/m<m>/` (CI artifact `flip-cell-<engine>`, never committed), and a per-element table in each JSON row (`elements.rows`: key, px, over, own, shareOfBox, shareOfDiff) |
| rules | which pixels count (max channel difference > 12), the pixel range floor(x)..ceil(x+w), share, m tolerance, scroll equality, the fade and the settled states are in lean/Fw/Parts/MorphGeomLookRule.lean; look-rule.mjs is a temporary JS stand-in checked line by line against the golden (test/look-rule.test.mjs, 14 tests) |

## Runs

| id | commit | what | result |
|---|---|---|---|
| 40553185213 | before | geom-page-diff look/on, both engines | baseline |
| 40585096601 | push 1 | message lacked `[ci:breakpoint-gate]`, every workflow skipped | no measurement |
| 40585231399 | push 2 (2909997c6) | flip-cell both engines | Chromium on+timed, WebKit on (flip verify A4 flake at 11 of 12 bands: baseline passed, WebKit timed hung at the wheel, job hit the 60 min timeout) |
| 40590730537 | dispatch on 2909997c6 | `fw run --gate` | Chromium on+timed complete and equal to run 1; WebKit flip-cell cancelled at the timeout |
| 40594241212 | push 3 (7775f52b4) | timed Chromium only, bands flushed, 22 min budget | Chromium on (identical to runs 1, 2), WebKit on, Chromium timed m=0 equalised but m=1 tween did not start on 9 bands |
| 40599995604 | push 4 (0f3242fb7) | on-dark copied onto base, nav colour wait; lanes breakpoint-gate and lean | success (all 11 jobs): Chromium on equal to runs 1-3, WebKit on (3rd JSON), Chromium timed m=0 near 0 and m=1 tween verified at 12 of 12 bands |

Pushes: 4 of 4. Chromium 'on': 3 jobs on separate CI jobs, equal to 4 digits (page share differs by at most 0.0001 between jobs). Chromium 'on' now 4 jobs (runs 1-4, page m=1 within 0.0001). WebKit 'on': 3 jobs with a JSON (runs 1, 3, 4; page m=1 equal to 4 digits in all 12 bands; run 4 also equal in m=0). The count of 3 is met for both engines. Tables: results/geom-look-fade/table-*.md, owners.md, look-summary.json.

## Result: page share (pixels over 12 in the whole viewport), flip vs base

morph.geom:on, Chromium, before (40553185213) -> after (40594241212); WebKit equal to 0.001 except where stated.

| band | m=0 | m=.5 | m=1 |
|---|---|---|---|
| 320x568 | 0.0002 > 0.0000 | 0.760 > 0.174 | 0.1135 > 0.0025 |
| 390x844 | 0.0003 > 0.0002 | 0.636 > 0.147 | 0.0907 > 0.0015 |
| 640x1000 | 0.0000 > 0.0000 | 0.542 > 0.102 | 0.0559 > 0.0007 |
| 641x700 | 0.0000 > 0.0002 | 0.769 > 0.112 | 0.1413 > 0.0284 |
| 768x1024 | 0.0102 > 0.0103 | 0.764 > 0.018 | 0.2095 > 0.0007 |
| 1280x800 | 0.0000 > 0.0000 | 0.733 > 0.018 | 0.0768 > 0.0005 |
| 1920x1080 | 0.0000 > 0.0001 | 0.811 > 0.013 | 0.4226 > 0.0003 |

At m=1 the page share falls from 0.056-0.423 to at most 0.0284 (641x700; every other band 0.0025 or less). The flip cell passes in run 4 on both engines (flip/on 48 of 48 rows ok, verify A3a/A4/A5 12 of 12 bands ok plus the 3+3 repeat bands; MEASURED run:40599995604). The WebKit A4 flake of run 1 (11 of 12) did not recur in runs 3 and 4; one flake in three WebKit runs. m=0.25/.5/.75 (nav, cols, page, 12 bands) are in table-on-*.md: nav falls from 0.31-0.78 to 0.011-0.196, cols from 0.1-0.93 to 0.04-0.35.

## What still differs, by element (results/geom-look-fade/owners.md)

- m=1, narrow bands (320-640 wide): `nav.bar.1.0` about 1900-1980 px constant, plus `nav-earn`/`nav-actions` (position of the EN button and the join pill, 400-1570 px). At wide bands (768-1920) only `nav.bar.1.0` about 300-390 px and column images of 12-98 px.
- m=1 at 641x700 (page 0.0284): `column3.img1` 2186, `column2.img0` 2180, `column1.img1` 1654, `column2.img1` 1241: picture footprint, owned by geom-image-model round 2.
- m=0.5 (a mid-flip frame): `nav-earn` ~4200 px, `nav.bar.1.0` ~3100-3200, `nav-lang` ~1100, column images (`column0.img0` 2800-9200) and the `footer` (blur in base, crisp in flip: 7000-78000 px at narrow bands) and the countdown clock at 640x360.
- m=0, 768x1024: page 0.0103, `column3.img0` 4706 px, in both engines and before and after (a picture at the tablet band).
- INFERRED: the footer and image differences at mid m are blur filters: the base arm is pinned at the value, the flip arm runs the compositor track; the nav differences are the position of the actions, not a colour.

## Timed (Chromium; WebKit dropped)

- m=1 (real wheel tween, runs 1, 2): nav 0.0004-0.0042 and page 0.0004-0.0052 at all bands, 641x700 highest. Equal in runs 1 and 2.
- m=0 untouched page, before the on-dark fix (runs 1, 2): nav 0.02-0.82 at bands 430 wide and up (page 0.0032-0.069). Cause (CONFIRMED by run 3, m=0 rows at 0.0000): the untouched timed page rests at m=0 at the page bottom with the nav marked `is-on-dark` by its own engine; base pinned the class from m (off at m=0).
- Run 3 removed the class on the flip arm: m=0 became 0.0000 at every band but the timed engine reads that class back as its own state, so the wheel no longer started a tween: 9 of 12 bands unverified at m=1 (those cells are not valid, marked `!` in table-timed-chromium.md).
- Run 4 (40599995604, MEASURED): the class is copied from the flip arm onto base after pinNav, flip arm untouched, 900 ms wait for the nav colour transition. m=0: nav 0.0000-0.0026, cols 0.0000-0.0033, page 0.0000-0.0002 at 11 bands and 0.0101 at 768x1024 (column3.img0 4706 px, the same picture as in look/on). m=1: the real wheel tween started at 12 of 12 bands (unverified=0, 60 cells, no `!`), nav 0.0004-0.0042, page 0.0004-0.0051 (641x700 highest), equal to runs 1 and 2. The m=0 fix works; the timed m=1 numbers did not change.
- The earlier timed rows (<= 0.001, run 40553185213) measured nothing: a pinned m starts no flip under geom-timed.

## Why WebKit timed is dropped

The wheel never started the tween under WebKit in run 1 and the job ran into its 60 min timeout. WebKit timed m=0 belongs to task timed-m0-webkit.

## General lesson

A pixel look that pins one state variable must pin every side effect the real driver writes for it (the platform fade), and its two arms must be read at the same scroll and the same m (asserted per cell). A comparison that pins a state the engine under test does not read (geom-timed, no observer) compares nothing and reports a low share.
