# Handoff: gate-breakpoints (PLAN 6.6 breakpoint parity gate, M2)

Package `packages/gate-breakpoints/` (README there). Branch `worktree-agent-afb44aba0417936b1`, based on main caa66e0.
Results of the one full run reported here: `packages/gate-breakpoints/results/summary.md` and `summary.json`
(raw run files are gitignored: 13.7 MB per engine, `out/run-a/<engine>.json`).

## Result (one full gate, both engines, 124 loads x 2 arms each, plus 4 sweeps)

Cells are `pass`, `FAIL probes-failing/probes-comparable`, or `NC` (not comparable). The two engines gave the same table
except the env row and one Lean cell (the WebKit cross block).

| row | desk (30) | desk-rm (30) | touch (30) | touch-rm (10) | phone-ls (2) | dw-arm (6) | hover x pointer (4) | dark (2) | fractional (4) | height (6) | sweep desk 1512-320-1512 (57) | sweep phone rot (5) | sweep touch 1024-1201 (5) | sweep pain 1440-600 (5) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| env achieved, Chromium | 30 | 30 | 30 | 10 | 2 | 6 | 4 | 2 | **0** | 6 | | | | |
| env achieved, WebKit | 30 | 30 | 30 | 10 | 2 | 6 | **0** | 2 | **0** | 6 | | | | |
| matchMedia orig = rewrite (both engines) | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| matchMedia = Lean (Chromium) | pass | pass | pass | pass | pass | pass | pass | pass | NC | pass | pass | pass | pass | pass |
| matchMedia = Lean (WebKit) | pass | pass | pass | pass | pass | pass | **NC** | pass | NC | pass | pass | pass | pass | pass |
| legacy max-/min- text = range text | pass in every cell, both engines | | | | | | | | | | | | | |
| engine.scroll | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC |
| nav.hitTest | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC | NC |
| hero.countdown | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
| hero.exit | FAIL 22/30 | FAIL 30/30 | FAIL 22/30 | FAIL 10/10 | FAIL 2/2 | FAIL 6/6 | FAIL 4/4 | FAIL 1/2 | FAIL 4/4 | FAIL 4/6 | FAIL 42/57 | FAIL 2/5 | FAIL 5/5 | FAIL 3/5 |

Sweep hysteresis (state after the sequence against a fresh load at the same final env, per arm, all four sweeps, both
engines): 0 differing items of about 1020 compared, original and rewrite alike.

### Why hero.exit fails (the distinct failing items; identical in both engines)

| role | property | where | original | rewrite | cause |
|---|---|---|---|---|---|
| copy | `padding-left/right` | every width > 600 (145 probes) | 24px | 0px | the rewrite omits the original's `.hero-copy { padding: 0 24px; position: relative }` at > 600 (2.gBuqKVzi.css:1725-1745) |
| copy | `position`, `top`, `left` | same 145 | relative / 0px / 0px | static / auto / auto | same omission (`position: relative` only restated inside <=600, as absolute) |
| copy | `filter` | reduced motion at > 600 and the landscape reduce probe (31) | none | blur(0px) | the original's reduced-motion rule sets `.hero-copy { filter: none }` (2.gBuqKVzi.css:2128-2160); the rewrite's reduced-motion block only resets height and position |
| cue | `filter` | reduced motion at <= 600 (10) | none | blur(0px) | same: original reduced-motion sets `filter: none` on `.scroll-cue` |
| track, hero, copy (w), cue/copy (left, transform) | width | width 319 (3 probes) | 320 | 319 | the original's page wrapper `.start-selling { min-width: 320px }` (2.gBuqKVzi.css:11745; PLAN 6.6 edge 319 to 320) is not restated, so its track is 320 wide at a 319 viewport and the rewrite's is 319 |

hero.exit passes (all compared items equal) at: desk and touch 320, 400, 401, 461, 462, 480, 481, 600; dark 430x932;
height 430x775 and 430x815. It fails everywhere above 600 and under reduced motion.

hero.countdown passes in all 124 probes and all sweep stops (881 items per probe, 136 for hero.exit: unit sizes 120/88/74, gap, radii,
padding, value/label font sizes, digit and face counts, ...). The C1000-nodw and <=400 conditions behave as the original.

Informational only (not in any verdict): properties the original declares for a compared element and the rewrite does not
restate. 5 distinct: the title's `display: flex / flex-direction: column / align-items: center` (rewrite: block) and the
`font-family` of the title and the lead (rewrite: its own system stack).

### What the gate cannot test (env not achieved, reported not hidden)

| item | engine | what | why |
|---|---|---|---|
| fractional gaps (600.5, 640.5, 860.5, 1000.5), 4 probes | both | the engine renders 601, 641, 861, 1001; Lean check is NC; A vs R is still compared at the whole px | no emulation takes a fractional viewport. Measured: an `<iframe>` of CSS width 600.5 at DPR 1.25 gets a 601 px media width (bisecting `(min-width)`) in Chromium and WebKit. The gap behaviour rests on the Lean proofs (`gap_iff`) only |
| hover x pointer cross, 4 probes | WebKit | (none, fine) and (hover, coarse) cannot be built; the probes ran as the closest pair and Lean check is NC | WebKit reads hover and pointer from the platform (WebCore `css/query/MediaQueryFeatures.cpp`: `hoverSupportedByPrimaryPointingDevice`, `pointerCharacteristicsOfPrimaryPointingDevice`); Playwright offers only `hasTouch`, which flips both to (none, coarse) |
| engine.scroll, nav.hitTest | both | NC in every cell | `part.json` lists no anchors; they render nothing and restate no CSS (their effect is rAF work, PL5). Nothing to compare at a breakpoint |

Other limits: Mac Chrome 155 headless (puppeteer-core), not the pinned container; Playwright WebKit 27.2, not Safari (no
toolbar, no Simulator; PLAN requires one Simulator check to close promotion). No touch events are emulated, only the media
pair. State is compared at scrollY 0 only. The date is pinned (2026-10-01T00:00+07:00) and `Math.random` seeded, in both arms.
Sweeps: in WebKit the context `screen` cannot change, so device width stays at the first stop's value during a sweep
(Chromium follows the Lean model); INFERRED harmless: device width only enters the conditions through the `<= 500` arm, and every desktop sweep stop is already <= 860 wide or far above 500. The touch 1024 stop has no Lean vector
(no matrix probe has touch at 1024), so its Lean cell uses the stops that do. The planned live reduced-motion and touch flips
are not in this run (the four sweeps above are).

## How the environment is emulated, per engine (also at the top of `src/engines.mjs`)

| feature | Chromium (Chrome 155, headless, not "mobile") | Playwright WebKit 27.2 |
|---|---|---|
| width, height, DPR | CDP `Emulation.setDeviceMetricsOverride` (live resize repeats it) | context `viewport` and `deviceScaleFactor` (live resize: `setViewportSize`) |
| device width and height | same call, `screenWidth` / `screenHeight` (`device-width` and `screen.width` follow it; integers) | context `screen` (fixed for the context) |
| hover and pointer | `--blink-settings=primaryHoverType,availableHoverTypes,primaryPointerType,availablePointerTypes` per browser process (one browser per pair; MEASURED all four pairs work); touch emulation not used | `hasTouch: true` only (both flip together) |
| reduced motion, colour scheme | CDP `Emulation.setEmulatedMedia` | context `reducedMotion`, `colorScheme` |
| network | `--host-resolver-rules` leaves only 127.0.0.1 | `context.route` aborts non-local |

Every probe reports what the page itself sees (`matchMedia` of width exact, hover, pointer, reduced motion, dark; `screen.width`;
DPR; `innerHeight`). `envDeviations` (verdict.mjs) lists any feature not delivered; the Lean check only applies when the list is empty.

## Anchors, compared and excluded (`src/anchors.json`, with the reason on every entry)

Compared properties are the longhands the rewrite's CSS-module rules declare for the element (union over every `@media` /
`@layer` block), read from the live CSSOM; their computed values are compared, original element by selector against rewrite element by
structure. Boxes are compared in CSS px relative to a reference element so the host offset drops out.

| part | roles (elements) | box dimensions | excluded and why |
|---|---|---|---|
| hero.countdown | root, unit x4, value x4, label x4, number x4, digit x8, spacer x8, face x64 (counts, PL0) | unit: x,y,w,h relative to the first unit; root: h | root x,y,w (host differs: shrink-to-content inside the original's copy vs a full-width block); every text-bearing box (value, label, number, digit, spacer, face: width and height depend on the placeholder text and font); face `transform` (JS spring); `animation*` |
| hero.exit | track, hero, copy, copyMain, title, lead, cue | track: w,h; hero: x,y,w,h relative to the track; copy: x,w relative to the hero | track x,y (page offset); copy y,h (content differs: the original also holds the countdown and the CTA); copyMain, title, lead, cue boxes (text, icon); cue `transform`, `top`, `bottom`, `right` (used values from its own content size); hero `--copy-in` (declared on another element in the original); cards (stand in for hero.orbit, JS geometry); the CTA button (different design); `animation*` (entrance owned by hero.orbit; the original is compared after the splash and every finite animation has finished) |
| engine.scroll, nav.hitTest | none | none | no anchors |

## The pass/fail rule: pure functions for a Lean spec (`src/verdict.mjs`, 14 unit tests in `test/`)

No decision lives anywhere else; the runner writes raw facts only and `summary.mjs` calls these.

| function | statement |
|---|---|
| `cellVerdict(statuses)` **the rule** | let A = statuses that are not `na`. `not-comparable` if A is empty; `fail` if some s in A is not `equal`; `pass` otherwise |
| `rollup(verdicts)` | `cellVerdict` over `verdictToStatus` (pass to equal, fail to differ, not-comparable to na): probe to block to table |
| `styleValueEq(a, b)` | a = b as strings, or the strings are equal after replacing every number by a hole, with the same count of numbers and every pair within 1e-3 (PLAN PL2). Missing is never equal |
| `boxEq(a, b)` | both numbers and `abs(a - b) <= 0.5` (PLAN PL1) |
| `countStatus(a, b)` | both 0: `missing`; a = b: `equal`; else `differ` |
| `isSkipped`, `comparedProps` | restated set minus the role's skip names, skip sets and prefixes (`animation`, matching `animation` and `animation-*`) |
| `relBox(item, ref)` | the item's rect minus the reference item's x,y; w,h unchanged |
| `partItems(...)` | the items of a part: one count per role, then per element the box dims and the compared properties; original-only properties are `info` items with status `na` |
| `sameSideOfEdges(a, b, pairs)` | for every pair [n, n+1]: (a <= n) = (b <= n) |
| `envDeviations(requested, raw, deviceEdgePairs)` | features not delivered: width not exact, height, device width (allowed if on the same side of 500/501), DPR, hover, pointer, reduced motion, scheme |
| `truthItems(orig, rewrite, expect, expectNeutral, achieved)` | per condition: A = R always; = Lean only when `achieved` and a vector exists (else `na`); legacy text = range text per arm; same for the neutral queries |

Tolerances: boxes 0.5 CSS px, style numbers 1e-3, both PLAN 6.6. (The brief said exact for discrete values; computed styles are
compared as exact strings first, numeric slack applies only to numbers inside a value, per PL2.)

## Determinism

Two full runs of both engines made at the same time (concurrency 3 each, so under load) are **byte-identical** (`cmp`; sha256
chromium.json `4cb8952c5625...`, playwright-webkit.json `a06a13ff6150...`, summary.json `099a09e5ec4d...`), no retries. The first pair
of runs was not identical: the original's headline is animated text and its boxes moved between runs. Boxes are now only
collected where they are compared or used as a reference.

## Use

```sh
pnpm --filter @fw/site build                       # needs lake for the byte check; produces apps/site/dist/aot
cd packages/gate-breakpoints
node src/cli.mjs run --engine both --out out/run-a --concurrency 3   # about 20 min on this Mac (15 Chromium, 5 WebKit)
node src/cli.mjs summary --out out/run-a
node --test "test/*.test.mjs"
```
`--probes desk-601,touch` and `--sweeps none` run a subset (a block id or an id substring). Needs `snapshot/site` of the main checkout
(or `FW_SNAPSHOT_SITE`) and Google Chrome (or `CHROME_PATH`). `playwright-core` and `puppeteer-core` versions match `apps/site`.

## For the lead

- Parts not fixed, as asked. The five hero.exit causes above are the work list for part-hero (restate `.hero-copy` padding and
  position at > 600, the reduced-motion `filter: none` on copy and cue, and the 320 px floor, which belongs to the page wrapper).
- The fractional-gap probes need a different mechanism (a headed browser at browser zoom, or an accepted Lean-only proof); decide before M2.
- Before promotion: the Simulator check, and PL3 pixels (this gate is PL0, PL1, PL2 and the matchMedia truth; PL2b and PL3 are not in it).
