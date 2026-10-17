# 11 · Breakpoints: the inventory the rewrite must match

Kickoff research for v2, 2026-10-17. **Your requirement:** the rewrite supports every breakpoint of the original
identically, for every part. This page is the merged result. The machine-readable form is
[`breakpoints.json`](breakpoints.json), which the breakpoint lint and the breakpoint gate read (PLAN §6.6). The raw sweeps are
[`raw-css.md`](raw-css.md), [`raw-js.md`](raw-js.md) and [`raw-v1.md`](raw-v1.md). A verification pass corrected
them, and its fixes are folded in here.

> Personal, educational study of the public homepage https://fastwork.com/ (not affiliated with Fastwork). Source:
> the frozen snapshot `b1789284481295-a455e793` (`site-pretty/`, read-only). This page and the JSON hold only
> conditions, file:line citations and plain-language effects. They contain no Fastwork code.

Status words: **CONFIRMED** (the snapshot line cited says so), **INFERRED** (a cascade reading or plan, not yet
measured), **MEASURED** (a run).

## 1. Counts

| item | count | status |
|---|---|---|
| distinct media conditions, after normalising to range syntax | **30** (29 in CSS, 1 in JS only: `(hover: none)`) | CONFIRMED |
| of those, used by both CSS and JS | 6: `<=600`, `<=860`, `>=861`, C860, C1000, reduce | CONFIRMED |
| CSS `@media` blocks / direct rules | 92 blocks (1 nested) / 418 rules (+5 `@keyframes`) | CONFIRMED |
| JS `matchMedia` call sites | 29 (17 of them for reduced motion) | CONFIRMED |
| non-media gates (width reads, viewport-height bands, hit tests, the 320 floor, the viewport meta, safe-area, ungated `:hover`) | 20 | CONFIRMED |
| edges, as (feature, N → N+1) | **18**: 15 viewport-width edges, device-width 500, the touch clause at 1200, and one container width (1100) | CONFIRMED |
| `@supports`, `@container` queries, orientation, resolution, height queries, `any-*`, DPR code, multi-URL `srcset` | 0 | CONFIRMED (grep) |

The combos are comma lists, so they mean OR. Each pairs a width with a small device or a touch tablet:
- **C860, C1000, C1030** = `(width<=N px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)`.
- **C1000-nodw** (countdown, `2:1473`) is the same as C1000 **without** the device-width arm. Keep it separate.

## 2. Edges × parts

Edge "N" means the pair N | N+1 (the last px of the lower band | the first px above it). File keys:
- `2:` is `_app/immutable/assets/2.gBuqKVzi.css`;
- `N2:` is `_app/immutable/nodes/2.DyWL8TcE.js`.

| edge | gated by | conditions | parts |
|---|---|---|---|
| 319→320 | CSS floor | root `min-width: 320px` (`2:11745`); below it the page scrolls sideways | engine.scroll, theme.tokens |
| 400 | CSS | `<=400` | hero.countdown, morph.countdown |
| 461 | CSS | `<=461` | people.carousel |
| 480 | CSS | `<=480` | people.deck |
| device-width 500 | CSS + JS | C860, C1000, C1030 (not C1000-nodw) | commission, nav, morph.panel/tween, pain.notes, people.card/deck, platform, platform.stageBg/sweep |
| 600 | CSS + JS | `<=600` (CSS ×3, inline `max-width:600px`, JS `N2:4157`, `N2:12980`), `>600`, `601-1279`, `601-1511` | hero, hero.accent/cue/deck/exit/orbit, morph.panel, nav, overlays.signup |
| 640 | CSS | `<=640` ×6, `>640`, `641-1000` | commission, morph.columns/panel/tween, nav, nav.langMenu, overlays.drawer, people.card/deck, platform, platform.stageBg |
| 720 | CSS | `<=720` ×2 | morph.panel, platform |
| 860 | CSS + JS | `<=860` (CSS ×5, JS ×5), `>=861` (CSS ×2, JS `N2:10783`), `>=861 and no-preference` (nested), `861-1000`, C860, the computed-sticky check (`N2:12966`) | commission, morph.panel/tween, nav, overlays.drawer/signup, pain, pain.notes, people.card/carousel/deck/o, platform, platform.stageBg/sweep, ui.shared |
| 960 | CSS | `<=960` | platform, platform.stageBg |
| 1000 | CSS + JS | `<=1000` ×2, `>=1001`, `>=1001 and no-preference`, `641-1000`, `861-1000`, C1000 (CSS `2:916` + JS `N2:3085-3099`), C1000-nodw | commission, hero.countdown, morph.countdown, morph.panel, platform, platform.sweep |
| 1030 | CSS | C1030 ×11 | people.deck |
| container 1100 | JS | pain-notes container width < 1100 (`N2:4592-4645`); the viewport width where this happens is still to be MEASURED | pain.notes |
| 1100 | CSS | `<=1100` | platform |
| 1200 | CSS | plain `<=1200` ×3 (a desktop band at 1031-1200, no touch clause) | people.deck |
| 1200, touch | CSS + JS | the touch arm of C860, C1000, C1030 and C1000-nodw | 12 parts (as for device-width 500, plus hero.countdown and morph.countdown) |
| 1279 | CSS + JS | `601-1279` (`2:2026`) and the splash-stage check against 1280 (`N2:4192`, only during the splash) | hero.orbit |
| 1511 | CSS | `601-1511` | hero.orbit |

Reduced motion (35 CSS blocks, 17 JS sites), `no-preference` (5 blocks), `(hover: hover)` (sb-button), `(hover: none)`
(an unused tooltip) and `(prefers-color-scheme: dark)` have no px edge. They touch 27 PLAN parts, plus the 4 labels
that do not have a PLAN id yet. In all, the inventory maps to 31 PLAN parts and those 4 labels. Reduced motion
changes **layout** as well as motion: the hero track height and the pain, commission and profile sticky elements all
change.

## 3. JS-gated and CSS-only

- **JS-gated** (a rewrite driver must run the identical query and update the same way):
  - `<=600` OR reduce:
    - ring splash: a change listener finishes it, and widening never restarts it;
    - nav chrome-ready.
  - `<=860` (pure width):
    - people.o preview off;
    - pain note layout (a listener plus a ResizeObserver);
    - pain-dark (a listener);
    - an inert sheet store.
  - C860:
    - compact profile deck (a listener);
    - note drag off.
  - `>=861` AND NOT C860 AND NOT reduce: the desktop scroll-driven deck, polled per frame.
  - C1000: commission compact. It is **polled per scroll/resize frame with no change listener**, so a pointer-only
    change lands at the next frame (INFERRED).
  - Width reads:
    - the splash stage against 1280;
    - the pain container against 1100;
    - the fee visual: min(0.8, parent / 432);
    - the preview: min(320, innerWidth − 24);
    - the deck scale: min(1.22, …);
    - the waitlist dialog: min(360, 100vw − 48).
  - The countdown cell height comes from a ResizeObserver, so it follows the CSS font size at 400 and C1000-nodw.
  - Viewport-**height** gates with no width gate: morph arm 0.45 vh, commission bands, future shrink band, scene
    activation, hit test.
- **CSS-only:** every other edge (400, 461, 480, 640, 720, 960, 1030, 1100, 1200, 1511), the hero deck vs orbit
  choice (CSS `2:2031`, not JS; this corrects 02 §2.2), and the shrink neutralisation (`2:10990`; the JS shrinks
  have no width gate).
- **Never mix pure 860 and C860.** A touch tablet at 861-1200, or a phone in landscape (device-width ≤ 500), takes
  the desktop path for people.o, the pain layout, pain-dark and notes hidden, and the compact path for the deck, note
  drag and shrinks.

**Overlaps.** On a touch tablet at 861-1200, or in landscape with device-width ≤ 500, both C860 and `>=861` match.
C1000 and `>=1001` also both match (`overlaps` in the JSON).
- People: `2:3384` wins on position, but `2:3267` (specificity 0,2,0) beats `2:3468` (0,1,0), so inactive shells stay
  hidden.
- Platform: `2:5818` is later than `2:5672` and wins.
- The visible outcome is INFERRED. Measure it at 1024t and 932×430.

**Fractional gaps.** At 600.5, 640.5, 860.5 and 1000.5, neither `<=N` nor `>=N+1` matches. The rewrite must restate
each bound exactly.

## 4. The test matrix the parity gate runs

PL0-PL3, original vs rewrite with a per-config A/A, in Chromium and Playwright WebKit. The breakdown is in
`matrix.estimate`: **124 loads per engine** (INFERRED arithmetic), plus one Simulator check.

| block | inputs | where | loads |
|---|---|---|---|
| edge pairs, desktop | hover, fine pointer, DPR 1, no-preference | all 15 width pairs (319/320 … 1511/1512), height 900 | 30 |
| edge pairs, desktop, reduced | same, reduce | all 15 pairs | 30 |
| edge pairs, touch | hover:none, coarse, DPR 3 at ≤ 500 px and 2 above | all 15 pairs | 30 |
| touch, reduced | touch + reduce | 600, 860, 1000, 1030 and 1200 pairs | 10 |
| phone landscape | 932×430 on a 430×932 screen, touch, DPR 3, both motion settings | both overlaps | 2 |
| device-width arm alone | fine pointer, screen 500 vs 501, viewports 1001, 1031, 1201 | flips C860/C1000/C1030, not C1000-nodw | 6 |
| hover × pointer cross | (none, fine) and (hover, coarse) at 1024 and 1200 | no combo may match | 4 |
| dark | `prefers-color-scheme: dark` at 1440 and 430 | must equal light | 2 |
| fractional gaps | 600.5, 640.5, 860.5, 1000.5 via DPR 1.25 / zoom | neither side matches | 4 |
| height probes | 1440×822/823/900/901, 430×775/815 | profile clamp knees at heights 823/900; iOS toolbar heights | 6 |

**DPR.** Use DPR 1, 2, 3, plus 1.25 and 2.625 for the fractional probes. The page has no DPR-dependent code, so DPR
changes only the raster and fractional CSS widths.

**Live resize.** Compare the rewrite after a sequence with the original after the **same** sequence, because some
original state depends on the path (the splash never restarts).
- `desk-down-up`: 1512 → … → 320 → back up, crossing every edge both ways.
- `rotate`: 430×932 ↔ 932×430.
- `touch-1024`: 1024 ↔ 1201 with touch.
- v1's 1440 > 600 > 1440 pain sequence. The original is non-deterministic here, so accept either A/A class.
- Live flips of reduced motion and of touch on/off (the commission poll).

**Continuous sizes** between edges (clamp knees 889/1422, 875/1500, 462/769, 636/909, 900/1200, 400/500, the orbit edge
push, `cq` units, viewport units) are listed under `continuous`. The edge pairs above do not cover these sizes. The
gate samples one width inside each band.

## 5. What v1 missed

- **Edge pairs.** v1 ran only 600/601 as a pair. It never ran 860/861, 1000/1001, 1279/1280 or 1511/1512 as pairs,
  and it never named 400, 461, 480, 640, 720, 960, 1030, 1100, 1200 or device-width 500/501.
- **Conditions.** v1 folded C1000-nodw into C1000. It did not log `>600`, `>640`, `>=1001` or `641-1000`. It also left
  out:
  - the non-page sheets: `(hover: hover)`, dark, 5 reduced-motion blocks in DialogHeader;
  - the second JS 600 gate (`N2:12980`) and the 860 store (`N2:7179`);
  - all JS width reads, `cq` units, clamps and dvh/svh;
  - the 320 floor, the viewport meta, safe-area, and the 16 ungated `:hover` rules.
- **Its README was wrong in two places:**
  - "a tablet takes the phone path": it takes **both** paths;
  - the hero JS 600 gate picks the deck: it only skips the splash.
- **Runs never done:** fractional gaps, the live-resize sweep (planned, never run), WebKit beyond 430/980/iPad
  portrait, iPad landscape, real phone landscape with the toolbar, WebKit with reduced motion.

## 6. How the rewrite enforces it

1. **Generated inventory.** The snapshot extractor (L3, golden files) regenerates `breakpoints.json`. Each condition
   is normalised to range syntax, and legacy forms are kept in `equivalentForms`. Each use records its site, CSS or
   JS kind, parts, rule count and a sample of property names. Nobody edits it by hand. This file is the first
   golden.
2. **Breakpoint lint** (in `fw gate --part`; the set check is an L1 decision in `fwcore`). For each part and kind
   (CSS / JS), the set of normalised conditions in its CSS Modules and drivers must **equal** the inventory's set for
   that part:
   - an extra condition fails;
   - a missing one fails;
   - a shifted bound fails (`<601` is not `<=600`; pure 860 is not C860);
   - a `useMediaQuery` for looks fails (S10).

   Per condition, the rewrite's properties must cover the original's property names. Rules covered by the overlaps
   must keep the source order and specificity winner.
3. **Breakpoint gate**, required before any part is promoted (`faithful-with-delta` never waives it): the §4 matrix,
   PL0-PL3, both sides of every edge pair, the feature combos, the DPRs, the fractional probes, and the live-resize
   sequences compared with the original after the same sequence. Each PR runs the core matrix (430×932 and 430×775/815
   at DPR 3 with touch; 375×667 and 1440×900 at DPR 2; reduced motion) as the fast subset.

Open items:
- The parts `ui.shared(sb-*)` and `theme.tokens`, and the section shells `hero` and `platform`, need PLAN ids.
- The container-1100 viewport edge and the overlap outcomes are still to be MEASURED.
