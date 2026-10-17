# Raw list: breakpoint logic in the original's JS

Sweep of every JS file in the frozen snapshot `OLD/site-pretty` (read-only). Files swept: `_app/immutable/nodes/{0,1,2}`,
`chunks/*`, `entry/*`, `analytics.js`, the inline boot script in `index.html`, and (grep only) the vendored
third-party scripts under `__vendor/`. Line numbers are 1-based in the prettified files.
Short names: **N2** = `_app/immutable/nodes/2.DyWL8TcE.js`, **UI** = `chunks/D313Dngs.js` (bundled UI kit +
floating-ui), **RT** = `chunks/BSBv9QXB.js` (Svelte 5 runtime), **CSS** = `assets/2.gBuqKVzi.css`.
Every row is CONFIRMED by reading the cited lines unless marked INFERRED. No Fastwork code is copied: conditions are
media-query strings or plain-language comparisons.

## 0. The width / input classes JS uses

| name used below | condition | edges (CSS px) |
|---|---|---|
| **phone600** | `(max-width: 600px)` | 600 / 601 |
| **w860** | `(max-width: 860px)` (pure width) | 860 / 861 |
| **desk861** | `(min-width: 861px)` | 861 |
| **combo860** | `(max-width: 860px), (max-device-width: 500px), (hover: none) and (pointer: coarse) and (max-width: 1200px)` | 860, device 500, coarse 1200 |
| **combo1000** | three separate `matchMedia` calls OR-ed: `(max-width: 1000px)` or `(max-device-width: 500px)` or `(hover: none) and (pointer: coarse) and (max-width: 1200px)` | 1000, device 500, coarse 1200 |
| **rm** | `(prefers-reduced-motion: reduce)` | n/a |
| **hoverNone** | `(hover: none)` (UI kit tooltip only) | n/a |

Note: w860 and combo860 differ. A touch tablet at 768-1200 px, or a phone in landscape (device-width <= 500 on iOS),
matches combo860 but not w860 when its width is > 860. Which query a part uses matters for parity.

## 1. Per-part list (`matchMedia`, width reads, listeners)

| # | part | condition / measurement | edges | what it switches | how it updates | site |
|---|---|---|---|---|---|---|
| 1 | hero.orbit (ring splash) | phone600 or rm | 600/601 | at load (and on `pageshow` from bfcache) skips the 1820 ms ring-splash rAF loop and marks the splash done at once; otherwise runs it | `change` listener: when phone600 starts to match, finishes the splash; widening never restarts it | N2 4156-4157, 4220-4229, 4234-4238 |
| 2 | hero.orbit (splash geometry) | stage `clientWidth` (fallback `innerWidth`) compared with 1280; design canvas 1512 x 779 | 1280 | while the splash is in its "expanding" phase, cards are pulled inward by (1280 - stageWidth) x 0.35 px when the stage is narrower than 1280; no pull at >= 1280 | read every splash frame | N2 4033-4034, 4100-4110, 4192 |
| 3 | hero.orbit (scatter) | none (units vw / vh) | none | exit scatter targets are +-48vw and -22vh / 32vh / 10vh / -8vh by card position | static per card | N2 4115-4118 |
| 4 | hero.exit | rm only (no width gate in JS) | n/a | rm: `--exit-opacity` pinned to 1; else = 1 - scrolled/(trackHeight - innerHeight); pointer-events off below 0.05. The width-dependent exit translate and the deck-vs-orbit choice are CSS only (`.mobile-deck` hidden by default, shown under `@media (width<=600px)`, CSS 1967-1968 and 2031-2072) | scroll/resize rAF engine | N2 4163-4172 |
| 5 | hero.countdown + morph.countdown (digit) | Svelte `bind:offsetHeight` on the digit spacer (RT ResizeObserver, border-box) | follows CSS font size per breakpoint (v1: cell 31 / 36 / 52 px) | face `translateY` = slot offset x measured cell height (px); faces are not rendered until the height is > 0; rm (Svelte `MediaQuery` store) skips the spring and jumps | ResizeObserver on the spacer, so live on resize | N2 3817, 3829-3833, 3858-3873; RT 3110-3137 (`Ca`) |
| 6 | hero.accent | rm (one-shot) | n/a | rm: the accent-word cycle never starts | read once at mount | N2 3681 |
| 7 | nav (hero chrome) | phone600 or rm | 600/601 | `is-hero-chrome-ready` set at once; otherwise after 1140 ms or when the hero has `is-ring-splash-done` | `change` listeners on both queries | N2 12979-12993, 13092-13093 (class at template 13225) |
| 8 | nav (scroll-hidden) | indirect: computed `position` of `.start-selling-profile-sticky` must be `sticky` | CSS makes it sticky only under `(width>=861px)` + `(prefers-reduced-motion: no-preference)`, and `position: relative` under combo860 (CSS 3248-3254, 3384-3392) | `is-scroll-hidden` / `is-profile-sticky-hidden` while the profile sticky is pinned | per scroll frame (getComputedStyle) | N2 12966-12977, 13001, template 13230-13231 |
| 9 | nav (on-dark) | hit test at the nav's centre (`elementFromPoint`) against section selectors | none (geometry) | `is-on-dark` when over `.pain` / platform / a shrinking commission | per scroll frame | N2 12950-12964 |
| 10 | morph.tween / morph.mount | no width gate; viewport height: platform rect height >= 0.45 x (`visualViewport.height` or `innerHeight`) and bottom <= that + 8 | vh-relative | arms wheel/touch scroll-jacking that drives `--morph` (680 ms tween); rm jumps; IntersectionObserver `rootMargin: 200% 0px` arms listeners | wheel/touch + scroll engine | N2 12691-12700, 13040-13047, 13082-13088 |
| 11 | people.o (seller preview) | w860 | 860/861 | hover/focus/click preview card is disabled at <= 860; preview width = min(320, innerWidth - 24), clamped 12 px from both edges, flips above when it would pass innerHeight - 12 (card 440 tall) | queried on each hover / focus / click | N2 6203-6217, triggers 6304-6307 |
| 12 | people.card (future shrink) + pain colour | w860 | 860/861 | at > 860, `.pain` always gets `is-pain-dark`; at <= 860 only once the showcase element's top is <= 0.5 px. The shrink itself (`--future-shrink`) has no width gate in JS (vh-based: bottom between 0.85 and 0.35 innerHeight); rm makes it a step at 0.5 | `change` listeners (w860 and rm) + scroll engine | N2 11285-11290, 11295-11326, 11360-11362 |
| 13 | people (reveal) | none (hero progress >= 0.72 or rm) | n/a | reveals #people | scroll engine | N2 11303-11309 |
| 14 | people.carousel (avatar loop) | rm | n/a | rm: avatar cycle does not run | at mount | N2 11341-11352 |
| 15 | people.deck (mode) | combo860 -> compact flag `T` | 860, device 500, coarse 1200 | compact (true): tabs `aria-orientation` horizontal; tab rail drag-scroll by pointer (4 px slop); snap-scroll tracking picks the centred shell (150 ms debounce + rAF + `scrollend`); renders the active shell and its +-1 neighbours; tab click scrolls rail + deck. Not compact: vertical tabs, only the active shell rendered | `change` listener on combo860 -> recompute, re-centre, rerun frame | N2 10783, 10817-10823, 10849-10903, 10913-10918, 11193-11199, 11242-11245, template 11237 |
| 16 | people.deck (scroll-driven desktop) | `ce()` = not rm AND not combo860 AND `(min-width: 861px)` | 861 | true: section height = deck height + 1.45 innerHeight + (n-1) x 0.34 innerHeight; `--profile-scale` and active-shell translate/scale eased from start scale min(1.22, (innerWidth - 112)/(deckWidth - 248)) to 1 over the shrink range, then the active tab follows scroll; tab click scrolls the page smoothly. False: height cleared, scale 1, transforms cleared, rail shown | per scroll/resize frame; rm `change` listener | N2 10780-10813, 10849-10860, 10919-10966 |
| 17 | pain.notes (base layout) | w860 (query string held in a local, N2 4415) | 860/861 | <= 860: mobile note set centred on an 860-wide design (x offset (containerWidth - 860)/2, top -16 px); > 860: desktop set centred on a 1440 x 868 design; notes 240 x 240 | `change` listener + ResizeObserver on the note box | N2 4555-4589, 4689-4709, 4733 |
| 18 | pain.notes (extra notes) | w860 or rm -> no extras; then container width < 1100 | 860, 1100 | every 3 s adds an extra note (max 12) only at > 860 and not rm; placement: width < 1100 -> jittered pick from fixed slots; >= 1100 -> 120 random scored samples; extras cleared once `.commission-card` top < 0.995 innerHeight | 3 s interval (armed when >= 12 % visible), query read each tick | N2 4592-4645, 4692-4702, 4724-4731 |
| 19 | pain.notes (drag) | combo860 | 860, device 500, coarse 1200 | drag to move a note is disabled under combo860 (also ignores non-primary mouse buttons); keyboard arrows still move notes | read on each pointerdown | N2 4647-4669, 4671-4686 |
| 20 | commission (compact) | combo1000 | 1000, device 500, coarse 1200 | class `compact` on the section; arrow image swaps to the compact SVG; runway spacer height = 0.06 innerHeight px only when not compact and not rm (else CSS value); `title-wrapped` detection (Range client rects > 1, plus a ResizeObserver) only when compact | re-evaluated each scroll/resize frame (no `change` listener on these three queries; an input-only change, e.g. pointer, waits for the next scroll/resize) | N2 3085-3091, 3093-3099, 3105-3127, 3141, 3294-3305 |
| 21 | commission (enter / exit shrink) | no width gate; vh thresholds: card top between 0.42 and 0.06 innerHeight; card bottom between 0.85 and 0.35 innerHeight; rm makes them steps at 0.5 | vh-relative | `--commission-enter-shrink`, `--commission-shrink`, `entering`, `shrinking` | scroll engine | N2 3075-3084, 3112-3124 |
| 22 | commission.typing (fee visual) | ResizeObserver on the parent: `--visual-scale` = min(0.8, parentWidth / 432) | parent width 345.6 (cap) | scales the fee visual linearly below a 345.6 px parent | ResizeObserver, live | N2 2511-2518 |
| 23 | commission.typing (loop) | rm | n/a | rm: final state at once, no typing loop | at each intersect | N2 2495-2498 |
| 24 | commission (why-bring overlay) | rm | n/a | close delay 480 ms vs 0 | on close | N2 2917-2919 |
| 25 | platform.entries (agents) | rm | n/a | rm: shows the first query and final state | at mount | N2 11607-11608 |
| 26 | platform (orders / invoice) | rm | n/a | rm state flag | at mount | N2 11861 |
| 27 | platform (credibility) | rm | n/a | rm: final state | at mount | N2 11995-12001 |
| 28 | platform.glint (secure network) | rm | n/a | rm: SVG `<animate>` restart loop off | `change` listener | N2 12197-12215 |
| 29 | platform (section shrink) | no width gate; bottom between 0.85 and 0.35 innerHeight; rm step at 0.5 | vh-relative | shrink value + `is-shrinking` | scroll engine | N2 12433-12449 |
| 30 | waitlist modal shell | w860 via Svelte `MediaQuery` store (module-level, N2 7179) | 860/861 | would render a bottom-sheet drawer at <= 860 when `mobilePresentation` is `sheet`; the only caller (waitlist) passes `dialog`, so on this page it is always the centred dialog. The store is still created and listened to | reactive store | N2 7179, 7323, 7389-7391; caller 13293-13305 |
| 31 | waitlist dialog (UI kit) | none (geometry): open-direction offset from the focused element's centre relative to the viewport centre (innerWidth/2, innerHeight/2), 16 px max | n/a | `--dialog-dir-x/y` for the open animation; width from caller `min(360px, calc(100vw - 48px))` (CSS) | on open | UI 1927-1933, 2005-2010; N2 13303 |
| 32 | UI kit tooltip | hoverNone | n/a | on hover-less devices pointer-leave does not schedule hide; no tooltip is used on this page (no `tooltip` prop passed; the only `role="tooltip"` is the people.o preview, which is separate) | per event | UI 1172-1181, 1898-1915 (INFERRED unused: grep of N2) |
| 33 | engine (scene activity) | viewport height: initially active when rect bottom >= -innerHeight and top <= 2 x innerHeight; then IntersectionObserver `rootMargin` default `100% 0px` (pain `150% 0px`) | vh-relative | `data-start-selling-scene` active/paused, deferred render with measured `--start-selling-intrinsic-block-size` | window `scroll` + `resize` -> one rAF | N2 2663-2680, 2689-2713, 2715-2718, 2722-2731, 2768 |

## 2. Searched and not found (or not breakpoint logic)

| search | result | site |
|---|---|---|
| `ontouchstart`, `TouchEvent`, `maxTouchPoints`, `GestureEvent` | none in the original (v1's `GestureEvent` gate was v1's own fix) | grep of all app JS |
| `devicePixelRatio`, `screen.width/height`, `orientation` media | none (the only "orientation" is ARIA) | grep |
| user agent | only Svelte runtime: Firefox uses `importNode` instead of `cloneNode` for templates; no visual effect | RT 1417, 2133 |
| `CSS.supports` | only floating-ui's WebKit check for tooltip positioning (unused here) | UI 478-480 |
| responsive images (`sizes`, `media=` on `<source>`, `w`/`x` descriptors) | none: every `srcset` has one URL; `<source>` picks by `type="image/avif"` only | index.html, N2 3475-3486 |
| `@container` / container-query JS | none | grep |
| `navigator.connection.saveData` | SvelteKit link preloading off on save-data; not visual | `chunks/CzkAa0og.js` 1265 |
| nodes 0 / 1, entry, `analytics.js`, inline boot script | no width / input logic (`analytics.js` watches classes, e.g. nav `is-expanded`) | `nodes/0.Z5L-ui-T.js`, `analytics.js` 213-226, index.html 66-89 |
| vendored Hotjar / Sentry / Amplitude / GTM | third-party, not part of the page's look; contain viewport reads (Hotjar modules 16 hits, Sentry 5) | `__vendor/` (grep counts only) |

## 3. JS edges to carry into the rewrite (union)

- Width edges: **600/601**, **860/861**, **1000/1001**, **1100** (pain container), **1280** (hero stage, splash only),
  **345.6** (fee-visual parent), **1512 x 779** and **1440 x 868 / 860** design canvases (centring offsets, not gates).
- Input edges: **device-width <= 500** and **hover:none + pointer:coarse up to 1200** (combo860, combo1000).
- Reduced motion: 17 JS reads (N2 2496, 2919, 3101, 3681, 3817, 4156, 4596, 6226, 10780, 10917, 11295, 11607,
  11861, 11995, 12197, 12435, 12979).
- Height-relative gates (no width): 0.72 hero progress, 0.06/0.42/0.35/0.85 x innerHeight bands, 0.995 x innerHeight,
  0.45 x visual viewport height for the morph, 1.45 / 0.34 x innerHeight deck ranges, scene margins 100 % / 150 % / 200 %.
- Update paths differ per part: `change` listener (hero, nav, people, deck, pain base), per-frame poll (commission,
  deck `ce()`), per-event poll (people.o, pain drag, pain extras), ResizeObserver (countdown, fee visual, pain box).
  A faithful rewrite must reproduce the path too: e.g. commission ignores a pointer-only media change until the next
  scroll/resize (INFERRED from code; not measured).
