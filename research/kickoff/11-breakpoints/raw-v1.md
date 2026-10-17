# 11 · Breakpoints: raw list of what v1 found (input to the v2 breakpoint inventory)

Raw extraction, 2026-10-17. Sources are the read-only v1 repo (`../fastwork-com-web-optimize`, "v1:") and its
frozen snapshot (`site-pretty/`, "snap:"). Paths are relative to the v1 repo root. No Fastwork code is copied: queries
are written as conditions and cited by file:line. Status words: CONFIRMED (cited source or v1 measurement record),
INFERRED (my reading), MEASURED-v1 (v1 observed it in its own setup; not re-run here).

User hard requirement this feeds: the v2 rewrite must behave like the original at every breakpoint, for every part.

Short names used below:
- `css` = `site-pretty/_app/immutable/assets/2.gBuqKVzi.css` (the page CSS; prettified, 1-based lines)
- `js` = `site-pretty/_app/immutable/nodes/2.DyWL8TcE.js` (the page node)
- `bpR` = `research/breakpoints/README.md`; `cfg` = `research/breakpoints/configs.mjs`; `v7` = `research/breakpoints/v7-check.md`
- combo-N = the touch combo "(width <= N) OR (device-width <= 500px) OR ((hover: none) AND (pointer: coarse) AND (width <= 1200px))"

## A. The v1 viewport matrix (14 configs + 4 stub configs + 2 Simulator setups)

CONFIRMED from `cfg:3-25`. "touch" = CDP mobile emulation + touch (maxTouchPoints 5), so hover:none / pointer:coarse
match (`research/breakpoints/sweep.mjs:98-101`). Reduced motion via `Emulation.setEmulatedMedia`.

| # | id | viewport (CSS px) | DPR | touch | screen override | reduced motion | why v1 picked it |
|---|---|---|---|---|---|---|---|
| 1 | c375 | 375x812 | 3 | yes | - | no | narrowest phone; <=400 band |
| 2 | c430 | 430x932 | 3 | yes | - | no | the calibrated phone (iPhone 15 Pro Max) |
| 3 | c600 | 600x960 | 1 | no | - | no | last px of the <=600 band |
| 4 | c601 | 601x960 | 1 | no | - | no | first px above 600 (only N/N+1 pair in the matrix) |
| 5 | c768t | 768x1024 | 2 | yes | - | no | tablet portrait: phone path via the coarse<=1200 arm |
| 6 | c900 | 900x900 | 1 | no | - | no | desktop just above 860/861 |
| 7 | c1024t | 1024x768 | 2 | yes | - | no | tablet landscape (combos match by touch) |
| 8 | c1024 | 1024x768 | 1 | no | - | no | same width, no touch (combos do not match) |
| 9 | c1280 | 1280x800 | 1 | no | - | no | first px outside the 601-1279 band |
| 10 | c1440 | 1440x900 | 1 | no | - | no | common desktop; inside 601-1511 |
| 11 | c1920 | 1920x1080 | 1 | no | - | no | wide desktop; outside 601-1511 |
| 12 | c932l | 932x430 | 3 | yes | 430x932 | no | iPhone landscape; device-width stays 430 |
| 13 | rm430 | 430x932 | 3 | yes | - | yes | reduced motion, phone |
| 14 | rm1440 | 1440x900 | 1 | no | - | yes | reduced motion, desktop |
| s1 | ge430 | 430x932 | 3 | yes | - | no | `window.GestureEvent` stub (WebKit-only path in Blink) |
| s2 | ge932l | 932x430 | 3 | yes | 430x932 | no | stub, landscape |
| s3 | ge1440 | 1440x900 | 1 | no | - | no | stub, desktop |
| s4 | germ1440 | 1440x900 | 1 | no | - | yes | stub, desktop, reduced motion |
| sim1 | fw-sim + viewport-980 overlay | 980 wide on a 430 device | 3 | finger | device portrait | no | WebKit >600 branch without rotating (`bpR:463-508`) |
| sim2 | fw-ipad (iPad Pro 13, portrait) | 1032x1244 | 2 | finger | - | no | real WebKit tablet; hover:none, pointer:coarse, combo860 and combo1000 true, `(max-width:1000px)` false (`v7:87`) |

Items:
- A1. The ge* stub configs are excluded from the default sweep (`research/breakpoints/sweep.mjs:31`). CONFIRMED.
- A2. bpR §3.3 says "all 15 configs" (`bpR:365`, `bpR:438`) but its census table has 14 config rows. INFERRED: a
  v1 miscount; the matrix is 14.
- A3. The v1 matchMedia truth table logged per config: max-width 400/600/640/860/1000/1030/1200, min-width 861,
  min-width 1280, max-width 1511, hover:none, pointer:coarse, max-device-width 500, reduce, combo860/1000/1030
  (`research/breakpoints/sweep.mjs:43-50`). CONFIRMED. It does not log 461, 480, 720, 960, 1100, the >600 / >640
  / >=1001 / >=641 forms, or the 1473 combo variant (item B6). INFERRED gap.
- A4. Proposed v1 gate (`bpR:545-594`, never built as a tool): run the 14 configs above, fix vs control vs A/A, 6
  stops (top, hero mid-exit, people, pain, commission, end), settle >= 2 s, countdown and accent masked; plus live
  resize across JS-gated breakpoints both ways; plus stub/Simulator for engine-gated paths; plus a census per width
  class. CONFIRMED (proposal text).

## B. Every breakpoint v1 listed, with source line and observed effect

v1's own list is `bpR:46-53`. Lines below re-checked against the snapshot by `grep -n @media` (CONFIRMED unless noted).
"Effect" is what v1 said or measured; v1 did not describe the CSS effect of most plain media blocks.

| id | condition (as written in the CSS, range syntax) | css lines | JS gate | effect recorded by v1 |
|---|---|---|---|---|
| B1 | width <= 400px | 1489 | - | countdown font 24 px, cell c = 31 px (`bpR:53`); cd-strip c follows a live resize 31/36/52 (`bpR:84`) MEASURED-v1 |
| B2 | width <= 461px | 3594 | - | listed only; effect not described |
| B3 | width <= 480px | 4635 | - | listed only |
| B4 | width <= 600px / width > 600px | <=: 2031, 5325, 11733; >: 1925, 11391 | `(max-width: 600px)` at js:4157 and js:12980 | hero layout/exit path splits here; hero-exit-threaded had separate CSS for >600 and <=600 inside no-preference and `heRest` picked translate by this query (`bpR:87`). c600 vs c601 pixels equal B vs S (`bpR:132-133`) |
| B5 | width <= 640px / width > 640px / 641-1000 band | <=: 1133, 3586, 7803, 10888, 11274, 11564; >: 11369; band: 1106 | - | listed only |
| B6 | width <= 720px | 7825, 10793 | - | listed only |
| B7 | width <= 860px (plain) | 899, 2305, 3519, 4093, 7798 | `(max-width: 860px)` at js:4415 (pain, `o`), js:6217, js:7179 (reactive query object), js:11296 | pain notes hidden by CSS (css 2305/2344) and the pain-notes interval not armed by JS while it matches; the touch combo does NOT hide them (`bpR:90`) |
| B8 | combo-860 | 3384, 3650, 5672, 10990 | js:4650 (pointer handler skip), js:10915 | future + platform "shrink" off; platform doc-sweep titles have a combo-860 variant (`inline`, 28 px) and a >=861 variant (`bpR:73`, `bpR:76`, `bpR:89`) |
| B9 | width >= 861px; 861-1000 band | >=861: 3248, 5818; band: 5624 | `(min-width: 861px)` at js:10783 (nav/desktop) | nav desktop branch; v1 cached it (`desktopMq`) and checked 600/601, 900, rm430, rm1440 (`bpR:74`) |
| B10 | width <= 960px | 10836 | - | listed only |
| B11 | width <= 1000px (plain); width >= 1001px; >=1001 AND no-preference | <=: 7753, 10651; >=1001: 5810; with motion: 226 | - | listed as a band only |
| B12 | combo-1000 | 916 | js:3087-3089 (commission `A()`, three separate queries ORed) | commission branch; 1024 touch = in, 1024 no-touch = out, 932x430 landscape = in via device-width (`bpR:72`) |
| B13 | width <= 1030px combo (combo-1030) | 3271, 3684, 3786, 4290, 4378, 4514, 4612, 4770, 4940, 5055, 5133 | - | listed in "touch combos" only (`bpR:50`); 11 blocks, effect not described |
| B14 | width <= 1100px | 7748 | - | listed only |
| B15 | width <= 1200px (plain) | 4484, 4508, 4935 | - | listed only |
| B16 | 601 <= width <= 1279 | 2026 | - | band listed; c1280 chosen as first px outside (INFERRED from the matrix) |
| B17 | 601 <= width <= 1511 | 2009 | - | band listed; c1440 inside, c1920 outside |
| B18 | prefers-reduced-motion | 28 top-level blocks + 1 nested at 3249 (inside the >=861 block at 3248) | reduce queried at js:2496, 2919, 3101, 3681, 4156, 4596, 6226, 10780, 10917, 11295, 11607, 11861, 11995, 12197, 12435, 12979; also a reactive object at js:3817 | under reduce the accent-word cycle never runs (js:3681, `bpR:75`); rm1440 hero photos have two load-dependent rasters (section D) |
| B19 | width-following sizes | hero title `clamp(40px, 4.5vw, 64px)` css:1764 | - | title font 40 px up to 888 px wide, 64 px from 1422 px; 46.08 px at 1024 (`bpR:53`, `bpR:170`) |

Items:
- B20. Three non-width inputs flip branches (`bpR:55-59`), CONFIRMED by v1 reading of the queries:
  touch (a 768 or 1024 coarse tablet takes the phone path of every combo up to 1200 px); phone landscape (iOS
  reports the portrait screen as device-width, so 932x430 is >600 and >860 but still matches every combo through
  device-width <= 500px); reduced motion.
- B21. JS gates v1 listed (`bpR:52`): commission `A()` = combo-1000; hero `(max-width: 600px)`; pain notes
  `(max-width: 860px)`; future and platform shrink = combo-860; nav/desktop `(min-width: 861px)`; reduced motion.
  CONFIRMED against js lines in the table.
- B22. Engine/input gates (not media queries) v1 met: `'GestureEvent' in window` + view-timeline support (hero-exit
  CSS mode, `bpR:87`); touch-only listener scope in nav-morph F3 (`bpR:88`). CONFIRMED in v1 notes; these were v1
  fixes, not the original's gates (INFERRED: the original has no GestureEvent gate; grep of js finds none).
- B23. Countdown cell c is read from a spacer's offsetHeight (Svelte `bind:offsetHeight`), so it follows a resize
  live: 31 (<=400) / 36 / 52 px desktop; fonts 24 / 28 / 40 px (`bpR:53`, `bpR:84`). MEASURED-v1.
- B24. Accent word geometry per width (same in baseline and every fix): widths 70 / 50 / 60 / 83.75 px at 40 px font;
  80.63 / 57.59 / 69.11 / 96.47 at 1024 (46.08 px font); 112 / 80 / 96 / 134 at 1440; neighbour moves per word
  change 10 / 5 / 11.88 px at 430, 11.52 / 5.77 / 13.69 at 1024, 16 / 8 / 19 at 1440 (`bpR:169-173`). The slide is
  in em (dw/128 em), so it is width-proof (`bpR:75`). MEASURED-v1. Useful as a v2 golden.
- B25. F3 hit-test coverage at the end of the page (8x12 grid, cells on #platform / nav of 96): 88/8 at 375-1024,
  90/6 at 1280 and 1440, 92/4 at 1920, 80/16 at 932x430 landscape (`bpR:369-410`). MEASURED-v1. A v2 golden per width.
- B26. Pages per width also differ in scroll length: scroll frames at vh/40 per frame were 254 (375), 233 (430),
  250 (600/601), 206 (768t), 318 (900), 331 (1024t), 386 (1024), 389 (1280), 368 (1440), 348 (1920), 509 (932l)
  (`bpR:369-404`). MEASURED-v1. INFERRED use: page height per config is a cheap v2 equality check.

## C. Edge pairs (N vs N+1) v1 tested or named

- C1. 600 vs 601 is the only adjacent pair in the matrix (c600, c601). Fix vs baseline within A/A at both, apart
  from accent-phase and entrance noise (`bpR:132-133`, `v7:25-26`, `v7:41`). MEASURED-v1. No edge bug found.
- C2. Named but not run as an adjacent pair: 860/861 (covered by c900, a 39 px gap), 1000/1001 (covered by c1024),
  1279/1280 (c1280 only), 1511/1512 (c1440 / c1920 only) (`bpR:72-76`). CONFIRMED that v1 did not run them.
- C3. Never named by v1 as edges: 400/401, 461/462, 480/481, 640/641, 720/721, 960/961, 1030/1031, 1100/1101,
  1200/1201 (also the coarse-pointer cut-off of every combo), device-width 500/501. INFERRED gap.
- C4. Fractional widths. The CSS uses range syntax with integer pairs that leave an open interval: "width <= 860px"
  vs "width >= 861px" (css 899 etc. vs 3248), "width <= 1000px" vs "width >= 1001px", "<= 640" vs ">= 641" (1106),
  and JS uses "(max-width: 860px)" vs "(min-width: 861px)" (js:6217 vs js:10783). A viewport whose CSS width is
  fractional (browser zoom, or a non-integer DPR such as 1.25 or 2.625 where innerWidth can be fractional) between
  860 and 861 matches neither side. ">600" vs "<=600" (1925 vs 2031) and ">640" vs "<=640" are complementary and have
  no gap. INFERRED (not measured by v1; v1 ran 412@2.625 and 1536@1.25 only for the countdown, item E1). v2 must
  copy these exact conditions, gap included, to be identical.
- C5. The commission JS gate (js:3087-3089) ORs three queries, while its CSS twin is one combo block (css 916). v1
  checked they agree (`bpR:72`, "the query matches the CSS (code)"). CONFIRMED by v1.
- C6. css 1473 is a combo-1000 variant WITHOUT the device-width arm: "(width <= 1000px) OR (coarse AND hover:none AND
  width <= 1200px)". v1's list (`bpR:50`) folds it into combo-1000. A fine-pointer device with device-width <= 500
  and width > 1000 is the only case where the two differ. INFERRED: no real device hits it, but v2 must keep the
  two distinct conditions.

## D. Findings per config (pixels, counts, errors) that set v2's bar

- D1. Errors: 0 exceptions / 0 console errors / 0 HTTP errors in every arm at every config (`bpR:10`, `bpR:128-143`,
  `v7:12`). The baseline mirror lacks two lazy-loaded files (`/selling/optimized/media/post-1.avif`, `post-2.avif`),
  which a baseline load at 768t requested once (2 console errors + 2 404s) (`v7:49`). MEASURED-v1; a mirror gap, not
  a breakpoint effect.
- D2. A/A noise floor per config and stop varies a lot (0 % to 1.167 %, `bpR:130-143`): c375 hero 1.167 %, c932l
  hero 0.677 %, c600 top 0.59 %, c1920 hero 0.442 %, c601 hero 0.428 %. Sources: hero accent word on a 3 s timer,
  entrance transitions (future card blur 14 px -> none, 1.6 s; nav earn sheen 0.52 s + 0.98 s), countdown clock,
  referral-fee count-up at 768t (`bpR:114-119`, `bpR:165-180`, `v7:42`). MEASURED-v1. v2 pixel gates need a per-config
  A/A, not one global floor.
- D3. The nav "EN" label lands at one of two sub-pixel x positions per load, in either build (22 CSS px, shade up to
  94); a two-load A/A can miss it (`research/management/ops-handover.md:1872-1873`, F-199). MEASURED-v1, cause unknown.
- D4. Reduced motion at 1440 (rm1440): the tilted hero orbit-card photos have two baseline renderings, "soft" (fast
  load, first-paint raster never repainted) and "sharp" (cold load, or any later repaint) (`bpR:182-361`). 3.05 % of the
  frame, max 118 levels, up to 11,983 CSS px² per card. Not seen without reduced motion (c1440) nor at rm430
  (`bpR:329-342`, `research/pixel-tolerance/README.md:165`). MEASURED-v1. User decision PR-015 "keep" (`bpR:360`).
  For v2: the original itself is not deterministic here; the v2 equality check at rm1440 must accept either class.
- D5. Census per width (layouts / style recalcs / paints / layers at rest, scrolling, end) for the baseline at all
  14 configs is in `bpR:369-410`; e.g. at rest the baseline does 105-147 layouts in 4 s at every motion config and
  0 layouts under reduced motion. MEASURED-v1. This is the cost baseline v2 is compared with per width.
- D6. Max layer counts during the scroll differ by width class: 138-154 at <= 601, 163-167 at 601/768t, 117-129 at
  900-1920 and 932l (`bpR:369-404`). MEASURED-v1.
- D7. iPad Simulator (WebKit, 1032x1244 DPR 2): no errors; remaining differences only entrance timing, a rotating
  avatar row, a blur entrance and the platform glint (`v7:85-101`). MEASURED-v1.

## E. Live-resize findings

- E1. Countdown (cd-strip owner, not the sweep): after a live resize from 430 to 768@2 and 1536@1.25, 0 of 21 frames
  differ; to 1440@1 within A/A; c follows the resize 31 / 36 / 52 (`bpR:84`). Fresh loads at 768, 1440 and 1536 do
  not compare at all: the A/A differs in every frame because the clock lands a sub-pixel apart between loads
  (OBSERVED, cause unknown). 412@2.625: 1 frame differs, and the A/A differs on the same frame. MEASURED-v1.
- E2. Pain-notes interval (rest-script owner): resize 768>1024>768>1024 - ticks twice per 1024 segment (gap >= 3000
  ms), no work at 768; 600>1440 same; 1440>600>1440>600>1440 - the middle 1440 segment differs run to run (2 ticks vs
  0) in both builds, logged cause: the pain-notes IntersectionObserver reports only "out" after the reflow (likely
  scroll anchoring) (`bpR:90`). MEASURED-v1. The original is not deterministic across this resize sequence.
- E3. The planned sweep resize mode (desktop 1440>1000>860>600>430>1440; phone rotation 430x932>932x430>430x932;
  stops commission and people) exists in code (`research/breakpoints/sweep.mjs:16-18`, `:165-192`, `:326-327`) but
  was never run: parked by the lead (`bpR:440-442`, `bpR:518-520`, `v7:107`). CONFIRMED not run.
- E4. Width-following JS that re-reads on resize (not media queries, so a resize changes it continuously; INFERRED
  from code, not measured by v1): a ResizeObserver sets a `--visual-scale` = min(0.8, parentWidth / 432) (js:2512-2515);
  the window `resize` listener at js:2678; the orbit uses the container's clientWidth or innerWidth (js:4192);
  a popover width min(320, innerWidth - 24) clamped 12 px from both edges (js:6207-6209); a carousel scale from
  innerWidth - 112 (js:10800); pain-note placement offsets by (width - 860) / 2 under (max-width: 860px) (js:4559-4560).
  v1 listed none of these as breakpoint-dependent.

## F. Things v1 could not explain or did not cover (open going into v2)

- F1. Why the rm1440 first-paint raster of the card photos is soft (`bpR:315-327`). UNRESOLVED; decode size, mips and
  filter quality were identical (`bpR:255-282`, Chromium `cc/tiles/gpu_image_decode_cache.cc` cited there).
- F2. Which st6-rb2 change repaints the card photos at ~0.8 s (`bpR:314`, `bpR:533`). Not traced.
- F3. Why st6-rb2 / v7 paint more and add layers at rest at every width (`bpR:537-538`, `v7:75-83`). Not attributed.
- F4. hero-exit-threaded at 980 px in WebKit: low-amplitude orbit-card differences beyond A/A, cause unknown
  (sub-pixel position or resampling) (`bpR:494-503`).
- F5. Countdown clock lands a sub-pixel apart between fresh loads at 768, 1440, 1536 (`bpR:84`). Cause unknown.
- F6. The nav "EN" sub-pixel flip (D3). Cause unknown.
- F7. rm1440 commission "0%" glyph edge flip (0.068 %, max 158): per-load, not reproduced under hard freeze (`v7:44`).
  Cause unknown.
- F8. Not covered at all (`bpR:510-521`, `v7:103-113`): WebKit at widths other than 430, 980 and the iPad portrait;
  true phone landscape with the dynamic toolbar (no rotate tool); iPad landscape; iPad and WebKit reduced motion
  (later `sim.mjs --reduce-motion` existed, `research/management/ops-handover.md:1870`); Mac Safari 1024-1920 with
  hover and without; finger input at tablet widths; live-resize crossings; timing at any width other than 430.
- F9. hero-exit residual "R2-iPad-AFP": an iPad Private Browsing window <= 600 CSS px with finger input still takes the
  phone path (`research/management/ops-handover.md:1875-1876`). v1 fix behaviour, not the original's; listed because
  it shows a split-view iPad window can be <= 600 CSS px wide with coarse pointer and hover:none. CONFIRMED in v1 notes
  (WebKit blog 14795 and WebPageIOS.mm cited there), not run.

## G. Omissions in v1's breakpoint list that the snapshot shows (spotted while citing)

All CONFIRMED by grep of the snapshot; effect not yet described.
- G1. Container queries context: `container-type: inline-size` at css:1600 and `container-type: size` at css:6975;
  container units at css:1569 (orbit unit = 100cqw / 302), css:6398 (scale 100cqw / 640px), css:6985-6993
  (cqw/cqh in hypot sizes). No `@container` rules. These scale continuously with the container, so every width is
  a "breakpoint" for them. v1 does not mention them.
- G2. 30 `vw` uses and 16 `clamp(` calls in css; v1 named only the hero title clamp (css:1764).
- G3. 14 lines with dvh / svh / lvh in css: their value changes with the iOS toolbar state, which v1 could not test
  (F8).
- G4. Other stylesheets: `DialogHeader.Qcgwm6ST.css:537` has a "(hover: hover)" block and 5 reduced-motion blocks
  (111, 438, 590, 637, 711); `0.ChGpbVhU.css:250` has "(prefers-color-scheme: dark)". A library chunk gates on
  "(hover: none)" (`site-pretty/_app/immutable/chunks/D313Dngs.js:1176`). v1's list covers only the page CSS/JS.
- G5. A second `(max-width: 600px)` JS gate at js:12980 and a reactive `(max-width: 860px)` object at js:7179; v1
  named one hero 600 gate and one pain 860 gate. Owning parts to be mapped in the v2 inventory.

## H. Other v1 docs that mention breakpoints (no new original-site breakpoints)

- `research/architecture/apple-smooth-scroll.md:43, 100, 139, 167-182`, `research/design-engineering/apple-math.md:72,
  365-389`, `research/architecture/apple-verify.md:153, 255`: Apple's pages (breakpoints 734 / 1068, per-breakpoint
  keyframe masks, refresh on breakpoint change). Pattern ideas only, not the original's breakpoints.
- `research/architecture/automated-benchmarks.md:567-570`: the commission `A()` queries (js 3087-3089) cached; compact
  breakpoints skip writes and the easing tail.
- `research/architecture/oss-rendering-libs.md:379`, `research/design-engineering/oss-mechanism-map.md:259`: cache
  offsets on ResizeObserver + breakpoint MQ + fonts.ready.
- `research/pixel-tolerance/README.md:14, 45, 165`: the sweep method (M3) and the rm1440 numbers.
- `research/01-initial-investigation/README.md:102`: "drop effects that are visually disabled on the current
  breakpoint (matchMedia)".
