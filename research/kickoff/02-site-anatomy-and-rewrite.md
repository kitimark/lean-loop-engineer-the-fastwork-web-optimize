# 02 · Site anatomy and the React + MUI rewrite as pluggable parts

Kickoff research note for the v2 loop-engineering experiment, written 2026-10-17. It is a design input for the plan architect, not a plan.

> Personal, educational study of the public homepage https://fastwork.com/, not affiliated with Fastwork. This note
> names class names, CSS/JS line numbers and file paths of the frozen v1 snapshot. It does not copy Fastwork code,
> text blocks, images or fonts.

**Scope.** The assignment has five parts:
- (a) what the homepage is made of, section by section, with animations, assets, breakpoints and the jank v1 measured;
- (b) how to split a React rewrite into plugin "parts" with feature-flagged variants, plus a deterministic clock and scroll driver;
- (c) how to prove the rewrite is "identical" to the original;
- (d) MUI's runtime-styling problem and a recommendation;
- (e) how assets stay out of git.

**Status words.**
- **CONFIRMED** means a cited source agrees: a doc, engine source, the snapshot file itself, or a v1 note that cites one.
- **OBSERVED(v1)** means v1's own measurements, quoted from the v1 note named.
- **INFERRED** means my reading or proposal, not yet checked.

**Path conventions.**
- `OLD/` = `../fastwork-com-web-optimize` (read-only).
- `JS` = `OLD/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`.
- `CSS` = `OLD/site-pretty/_app/immutable/assets/2.gBuqKVzi.css`.
- Line numbers are 1-based in the prettified snapshot `b1789284481295-a455e793` (`OLD/baseline.json`).

---

## 0. Decisions in brief

1. **The page is one SvelteKit (Svelte 5) route with 6 scroll sections, a fixed nav that morphs into a full-screen menu, and 2 overlays.**
   - It has 119 `@keyframes`, 82 `@media` blocks, 4 registered `@property`, about 30 `prefers-reduced-motion` blocks, and 13 rAF/interval drivers in one 13,510-line JS node.
   - About half of the platform-section animation CSS is dead: its markup is never rendered.
   - The rewrite must reproduce only what runs (§2.8). CONFIRMED (counts from the files; dead list from `OLD/research/gpu-props/README.md` §3.2).
2. **"Faithful" must mean two kinds of parity, not one.**
   - *Visual parity*: same pixels.
   - *Work parity*: the same per-frame engine work, meaning the same properties written, the same forced layouts, the same layer set.
   - A React port that looks identical but is cheaper or dearer than the original makes every later A/B meaningless.
   - So the `faithful` variant of each part reproduces the original's mechanisms on purpose, including the bad ones: rect reads in rAF, `--exit-opacity` on a subtree, 10 `will-change` faces per digit, `elementFromPoint` hit tests, the scroll-jack.
   - A *cost-signature* gate (§4.6) checks this. INFERRED (design), motivated by `OLD/research/knowledge-distillation/README.md` lessons 1-3 and 29 ("the cost was the rest of the page sharing its frames").
3. **Every part is a registered plugin with variants**, selected by URL query or a committed JSON preset. The resolution is total and deterministic:
   - unknown ids are errors;
   - conflicts are checked;
   - the resolved config is hashed into every result.

   Each part also gets ablation variants derived mechanically from v1's method: `frozen`, `nopaint`, `static`, and `box` (same box, no content) (§3).
4. **Time and scroll are virtualised from outside the app, identically for the original and the rewrite:**
   - Playwright `page.clock` for JS time;
   - `document.getAnimations()` seek for CSS and WAAPI animations;
   - Chromium `HeadlessExperimental.beginFrame` for frame-exact compositor captures;
   - a seeded PRNG.

   The rewrite reads time only through platform APIs, so the same harness drives both arms (§3.5).
5. **MUI: use it narrowly.**
   - Material UI's latest release is **v9.5.0 (2026-10-09)** and it still depends on Emotion at runtime. Pigment CSS (zero-runtime) is **on hold**. CONFIRMED (§5).
   - MUI's own animated widgets animate layout properties: the Tabs indicator transitions `left`/`width` after `getBoundingClientRect`. CONFIRMED (MUI 9.5.0 source, §5.2).
   - Recommendation:
     - plain CSS Modules for every parity-critical or animated part;
     - **Base UI** (`@base-ui/react` 1.9.0, MUI's unstyled library) for interactive behaviour (dialog, tabs, menu);
     - Material UI only for non-animated chrome, behind `enableCssLayer`;
     - a runtime guard that fails a measurement if any style rule is inserted after measuring starts;
     - "MUI vs plain" as an experiment variable of its own, not a hidden confound.
6. **Legal.**
   - Images and fonts never enter git. They are served from the locally pinned v1 snapshot by path.
   - The faithful port necessarily restates Fastwork's design values and copy. Treat it as "Fastwork-derived" under the 12 Oct 2026 permission, which covers "this study".
   - **Ask the user** whether the permission extends to a public React port before anything is pushed (§6).

---

## 1. Global facts about the original

| fact | value | status, source |
|---|---|---|
| framework | SvelteKit, Svelte 5 (`window.__svelte.v` add `5`), SSR HTML + hydration (`kit.start(... node_ids:[0,2])`) | CONFIRMED `OLD/site-pretty/_app/immutable/chunks/xihTtKlq.js` l.1; `index.html` l.62-80 |
| files | 1 HTML (SSR markup on one line), page JS node 13,510 lines, page CSS 11,770 lines, plus `app`, `0`, `DialogHeader` CSS; 7 chunks | CONFIRMED (`wc -l`) |
| CSS scoping | mostly global `start-selling-*` classes; 26 Svelte scopes (e.g. hero `svelte-1p2vpne` ×115, nav `svelte-1dcozpm`, accent `svelte-1fn2go6`, countdown `svelte-1666oc5`, profile widgets `svelte-1v32ze3`/`9ggcvl`/`ty4hd7`…) | CONFIRMED (grep of CSS) |
| assets | `OLD/site-pretty/selling/` 224 files, 24 MB (164 jpg, 22 png, 28 svg, 9 avif, 1 woff2 Playpen Sans); `_app/immutable/assets/` Google Sans latin/thai normal+italic woff2; `fonts/fastwork-Bold.ttf` | CONFIRMED (`du`, `find`) |
| image markup | 113 `<img>` and 40 `<picture>` in SSR; at 430 px wide, 167 `<img>`, 97 URLs, 65 raster loaded (10.3 MB wire, 164.7 MB decoded at natural size); **no `srcset` anywhere** | CONFIRMED (SSR count) / OBSERVED(v1) `OLD/research/image-cost/README.md` §1 |
| scroll engine | one passive `scroll`/`resize` listener → `rE` → one rAF `iE` → every registered callback; `dE()` registers callbacks; per-section IntersectionObserver gate (`rootMargin:"100% 0px"`) toggles `data-start-selling-scene=active|paused` | CONFIRMED JS 2663-2780 (`requestAnimationFrame(iE)` at 2668, IO at 2725); `OLD/research/01-initial-investigation/motion-inventory.md` |
| breakpoints | max-width 400, 461, 480, 600, 640, 720, 860, 960, 1000, 1030, 1100, 1200; touch combos `(width<=N),(device-width<=500px),(hover:none) and (pointer:coarse) and (width<=1200px)` for N = 860/1000/1030; JS gates mirror some of them (600, 860, 861, 1000 combo) | CONFIRMED `OLD/research/breakpoints/README.md` §1; JS 3087-3089, 4157, 6217, 10783, 11296 |
| nondeterminism | `Date.now()` countdown (JS 3933, `setInterval` 1 s at 3936) toward **`2026-11-02T12:00:00+07:00`** (JS 3905); `Math.random()` in pain notes (JS 4517-4553, 4633); `performance.now()` springs/tweens (2451, 3835, 4229, 13032); IO/RO timing; image arrival order | CONFIRMED (grep). **The countdown target is 16 days from today**: after it passes, the live and frozen pages render a different state, so every capture must pin `Date` (§4.3) |
| third parties | GTM/gtag (`onscrollend` 45-76 ms per scroll in Chrome 6x), Hotjar, Amplitude, Cloudflare beacon; v1 served local copies (`--vendors=local`) | OBSERVED(v1) knowledge-distillation lesson 20 |
| phone geometry used by v1 | 430×775 (scripted) / 430×815 (toolbar collapsed), DPR 3; docH ≈ 6035 | OBSERVED(v1) `OLD/research/design-engineering/middle.md` §1 |

---

## 2. (a) Inventory, top to bottom

DOM order comes from the SSR markup in `OLD/site-pretty/index.html`, outlined with a stack parser. The morph panel is not in the SSR markup: it is mounted later by JS (JS 12877-12879).

The doc tops in the table are OBSERVED(v1) at 430×775: `middle.md` §1.

| # | part (root selector) | doc top / height (phone) | position |
|---|---|---|---|
| P0 | **Top nav** `header.start-selling-top-nav` (logo, language switch, "Join" `is-earn` button) | fixed | fixed; becomes the morph panel host |
| P1 | **Hero** `section.hero-track` (200vh) › `.hero` (sticky, 100svh) | 0 / 1630 | sticky |
| P2 | **People** `section#people.start-selling-future` | 856 / 1327 (margin-top 1px − 100svh, overlaps hero) | in flow, z 3 |
| P3 | **Pain** `section.pain` (sticky 100 + hold 200svh) | 1408 / 2325 (margin-top −100svh) | sticky, z 1 |
| P4 | **Commission** `section.commission` | 2958 / 1197 (margin-top −100svh) | sticky on desktop only |
| P5 | **Platform** `section#platform.start-selling-platform` | 4155 / 1880 | in flow |
| P6 | **Morph panel** (`.start-selling-morph-*` inside the nav) | full screen at m = 1 | fixed |
| P7 | **Overlays**: signup `dialog.sb-dialog`; `.sb-drawer`/"why-bring" (fixed `inset:0`, closed) | n/a | fixed |
| P8 | Hidden SEO locale links `nav.site-locale-links` (outside the Svelte mount) | n/a | visually hidden |

### 2.1 P0: Top nav (`svelte-1dcozpm`, CSS 10556-11512 and 11296-11556; JS ~12940-13250)

- **Structure.**
  - Bar: logo `a.start-selling-top-nav-logo` (inline SVG) and actions.
  - Language switch `.start-selling-language-switch` (`svelte-1lc7nmb`, menu in/out keyframes CSS 11209/11219).
  - "Join waitlist" `button.start-selling-top-nav-btn.is-earn`.
  - Hero state `is-hero-pill`.
  - Inline `--morph: 0` on the header.
- **Animations.**
  - `backdrop-filter: blur(calc(20px*(1-var(--morph))))` plus a nested `backdrop-filter: blur(12px)`.
  - Transitions: background .7 s, width .68 s.
  - At load: "earn" unmask (`mask-position`, 0.98 s) and a sheen (CSS 11546/11556).
  - `will-change: width,height,border-radius,background`.
  - CONFIRMED by motion-inventory and the CSS keyframe list.
- **Script.**
  - A per-frame callback that the IO does not gate: `getComputedStyle`, 3-4 `getBoundingClientRect`, then `style.pointerEvents='none'` → `document.elementFromPoint()` (JS 12961) → restore.
  - That is a write-read-write forced layout every frame. CONFIRMED JS 12955-12963.
- **v1 cost.**
  - Chrome 6x: the nav callback ran 316-320 times per run and took 526-617 ms per run. It was nearly all of `iE`'s time (TOPICS N12).
  - Phone: layout ran 2.2-2.4 times per morph frame before `hit-skip`.
  - OBSERVED(v1) knowledge-distillation lesson 1.
- **v1 fixes (become variants):**
  - `hit-skip`: `elementsFromPoint()` skipping its own subtree, 0/1690 parity mismatches;
  - cached MQLs;
  - "write only on change";
  - nav colour from an observer, not a size read (v13a).

### 2.2 P1: Hero (`svelte-1p2vpne`; CSS 1523-2000, 1221-1420; JS ~3790-4240)

| element | what moves | driver and properties | v1 cost / status |
|---|---|---|---|
| `.orbit.from-ring` › `.orbit-stage-3d` (desktop: 10 `article.orbit-card`, 2 with `.float`) | load "ring splash" (`card-from-ring`, `ring-appear`, `copy-from-ring` keyframes CSS 1970-1995); `preserve-3d`, `perspective:1200px`; per-card `--orbit-rot/--orbit-enter-x/y/delay` inline vars (JS 4131-4138); `.hero.is-preparing` ends after a `setTimeout(…,1820)` (JS 4229) | CSS keyframes + inline vars; `will-change: transform, translate, scale, opacity` | load only; desktop |
| `.mobile-deck` (phones: 4 cards `.is-a/.is-b/.is-d/.is-e`, each with a cover `<picture>`, an avatar row and info) | scroll exit: translate/opacity from `--exit-opacity` | JS per frame: `.hero-track` rect → `--exit-opacity` on `.hero` (JS 4163-4172) → restyles the ~230-element subtree | modelled 5-12 ms per frame (style); fixed by **hero-exit-threaded** (scroll-driven, v6; Safari 26.4+ runs it threaded). An earlier `view()` timeline v2 added +11 ms at y≈700 (UNRESOLVED) (`OLD/research/design-engineering/hero.md`, `postmortem-hero.md`) |
| `h1` › `em.script-accent.is-vector.is-stroke` ("you", `svelte-1fn2go6`, Playpen Sans) | hand-drawn stroke erase/redraw about every 3-4.3 s; idle "boil" | `stroke-dashoffset` on 3 SVG paths (CSS 1277-1282), inline `width` transition (layout for 0.9 s per cycle, CSS 1231), `step-end` opacity boil (CSS 1292-1299; keyframes 1312-1366) | per draw (Simulator) about 57 style, 57 layout, 61 paint records; 45-60 ms frame pairs every 3.15 s at idle; WebKit treats dashoffset as an SVG layout diff (CONFIRMED `StyleDifference.cpp` per v1). Fixes: HEflip (layout-animations), boil-ca, accent-wipe (proposal) |
| `.countdown` (4 `.unit`: days/hours/min/sec, `svelte-1666oc5`, digit `svelte-1quva9c`) | digit roll at each 1 s tick | `setInterval(1 s)` + a rAF **spring per digit** (`GE` 3791, `KE` 3804, `$E` 3823; transform write at 3862) moving **10 `.face` spans per digit, each `will-change: transform`** (CSS ~1397-1416); never paused off-screen | about 80 face layers in this clock (+ the same in the morph panel); 1 Hz idle spikes 35-58 ms; on WebKit a face that leaves its clip loses its backing store and repaints on re-entry (CONFIRMED `GraphicsLayerCA.cpp` per gpu-props §4). Fixes: countdown-faces (3 slots), **cd-strip** (one strip per digit, identical by construction), **cd-roll-ca** (WAAPI roll, T2 only), hidden-skip |
| `.hero-cta-stack` (bell button with SVG icon, RSVP calendar link, waitlist note) | `.hero-cta:before` conic `@property --hero-orbit-angle` animation | CSS | **dead**: target is always `display:none` (F-015) |
| hero copy entrance | `--copy-in` (`@property`, CSS 1513) | CSS, never accelerated | load only |
| `button.scroll-cue` › `.scroll-float` | float loop (`scroll-float`, transform, compositor) + `filter: blur(calc(var(--exit-scatter)*18px))` on exit | CSS + the exit var | the `blur(0)` at rest repaints while scattering (TOPICS #7) |

- **Breakpoints.**
  - `(max-width:600px)` picks the mobile deck and the exit translate (JS 4157).
  - The title is `clamp(40px, 4.5vw, 64px)`.
  - The countdown font is 24/28/40 px, so the cell is c = 31/36/52 px.
  - CONFIRMED breakpoints §1.
- **Threshold coupling.** At hero progress 0.72 (JS 11310) one frame:
  - reveals #people;
  - flips `.pain` dark (`is-pain-dark`);
  - drops the nav's `is-hero-pill`.

  On the phone that is a 58.2 ms flip frame (Layout 13.9, Composite 23.7) followed by 43.3 ms (OBSERVED(v1) lesson 14). The rewrite must keep **one owner** for this threshold, or the faithful variant will not reproduce the triple flip.

### 2.3 P2: People `#people` (CSS 2358-3260, 3650-5200 for the profile widgets; JS ~10745-11660)

| element | what moves | driver and properties | v1 cost / status |
|---|---|---|---|
| `.start-selling-future-card` (white, `min-height:100svh`) | reveal at the 0.72 flip: `visibility:hidden; opacity:0; filter:blur(14px)` → visible over 0.7 s (opacity), 1.6 s (blur), 0.9 s (lift) (CSS 2393-2414); `will-change: transform, border-radius`; `--future-shrink` eased 22 %/frame in JS (JS 11303) even on phones, where CSS forces scale 1, radius 0 | CSS transitions + JS lerp | flip frame above; about 41 MB allocated in the flip (Simulator); Chrome cannot composite blur (reason 4096, CONFIRMED gpu-props §2). Fixes: shrink gated on the MQ (FINDINGS T1: Chrome 6x 66.5 → 71.6 fps), blur tail cut 1.6 → 0.9 s, **PR-041** instant reveal after a fast flick (look change, accepted), **g0.0m** pre-painted at opacity 0 (+22 MB) |
| `h2` "People still need pe·o·ple": `.start-selling-future-people-o` | the "o" opens into a row of faces: `grid-template-columns` 0.6042em → 5.25em and `height` over 0.92 s; faces animate `max-width/width/margin/border-width`; `people-o-peel/seed-out/vector-in/preview-in` keyframes (CSS 5332-5378); avatars `sellers/*/avatar.jpg` | CSS layout transitions, replayed on re-entry | 57 layouts while it grows (Chrome 6x); 26-38 ms per frame on the phone. Fix: FLIP without reads (people-gpu, PR-031, proposal-class) |
| `section#profile-showcase` › sticky › chrome: **6 tabs** (Sound Composer, Photographer, Video Editor, Graphic Designer, AI Automation, Web Developer) + `.start-selling-profile-deck` (x-mandatory scroll-snap, 6 `.start-selling-profile-shell`) | snap deck; tab `gap` transition (CSS 2928); `profile-fade`; per-role profile widgets (Svelte scopes: summary, about, **vinyl** spin, posts, rail, reviews/digest, card/grid, **feed** panel-in); `--profile-scale` lerp (JS 10928) | CSS + JS | shells `aspect-ratio:353/764; height:auto` relaid out on every iOS toolbar step: median largest layout 25.7 / 22.7 ms → 0.4 ms with `height: calc(100cqi*764/353)` (**g0.0j**, sticky-walk); a 373×344 feed rect repainted on every frame for y 1600-2500 (cause unattributed); six 402×857 panels ≈ 74 MB of layers |
| `.start-selling-future-community-pill` › `.start-selling-avatars.is-carousel` | an avatar rotates in about every 1 s | `avatars-exit` animates `width, flex-basis, margin-right, border-width` (CSS 2888); `{#if}` template swap (JS 11330-11356, 11415-11447) mounting fresh `<img>` whose pop ends at `opacity:1` | WebKit "presence flip" (opacity crossing 1 → layout diff, CONFIRMED `StyleDifference.cpp` per v1): a whole-view Layout ≥ 10 ms after 71/71 slide starts; fixed by st6 (clip-path/translate) + keeping slots mounted + resting at 0.999: 19-27 → 0 slow frames per run at rest |

### 2.4 P3: Pain `section.pain` (CSS 2166-2350, 5611; JS 4409-4740)

- **Structure.** `.pain-sticky` (sticky 100svh) holds:
  - `.pain-canvas`;
  - `.pain-copy` with `h2` "Freelancing is hard enough…";
  - `.pain-notes` › `.pain-notes-stage`.

  `.pain-hold` adds 200svh.
- **Motion.** A `setInterval(3 s)` (JS 4696) adds sticky notes (`pain-note-stick`) with **`Math.random()`** positions, rotation and colours (JS 4517-4553, 4633).
  - The notes are `display:none` at ≤ 860 px, but the interval still runs.
  - A per-frame callback reads `.commission-card`'s rect.
  - The section's background flip (`is-pain-dark`) happens at y ≈ 888, under the future card.
- **v1 cost.**
  - Desktop parked at the pain top: the engine runs at about 33 Hz with no input (scene-gate flap, N9).
  - The section background switch costs 10-20 ms per crossing. The fix was solid-colour composited layers (middle R2).
  - The rest-script fix arms the interval only when the notes are visible.
- **Rewrite note.** The faithful variant needs a **seeded** PRNG for the note layout, or no two captures match (§4.3).

### 2.5 P4: Commission `section.commission` (CSS 1-600, 7631-7738; JS ~2424-2520, 3040-3141)

- **Structure.**
  - `.commission-track` › `.commission-sticky` (sticky on desktop) › `.commission-card`.
  - Header: `h2` with `.commission-title-muted`/`-accent` and a hand-drawn `.commission-underline`. Its keyframes are `commission-underline-draw/enter` and `three-frame-zero/one/two`, which are `step-end` boils (CSS 115-216).
  - Two rows, `.is-direct` and `.is-referral`, each with a visual column and copy. The visuals hold:
    - typing text (28 ms per character);
    - `typing-caret` (`step-end`);
    - `fee-avatar-pop`;
    - client avatars (`selling/commission/*`);
    - a `.fee-progress` rAF **width** count-up with `filter:blur` children.
  - `.commission-runway`.
- **Script.**
  - Two rects → `setProperty('--commission-*')` → `d.style.height` → `Range.getClientRects()` (JS 3098). That is a forced layout right after style writes, every frame (JS 3101-3128).
  - On phones the scale/radius values are overridden by CSS, so the work has no visual effect.
- **Breakpoints.** `A()` = the 1000 combo (JS 3087-3089).
- **v1 cost.**
  - Typing: Chrome 1x commission layouts 226 → 97 when typing two characters per step (typing-chunks).
  - WebKit runs an interleaved layout inside style recalc under size containers (CONFIRMED, lesson 7).
  - Fixes: commission-forced-layout (read first, line count moved to a ResizeObserver), shrink gated off on phones.

### 2.6 P5: Platform `#platform` (CSS 5388-10400; JS ~11600-12440)

- **Structure.**
  - `.start-selling-platform-card` › layout › mission header ("Built…" title `p#built-heading`).
  - 4 `article.start-selling-platform-row`, each with a stage and copy:

    | row | class | stage background | copy |
    |---|---|---|---|
    | 1 | `is-document` | mesh bg + `grain` overlay | "Document your portfolio and reviews" |
    | 2 | `is-flip` | `<picture>` stage | "Get discovered. Earn more" |
    | 3 | `is-payment` | mesh bg + grain | "Secure payment worldwide / Payment Protection / Daily Withdrawal" |
    | 4 | `is-flip` | `<picture>` stage | "Maintain relationship… / Keep every order Organized" |

  - Each stage visual is one of these sub-components:
    - cred cards plus a reviews marquee (90 s / 56 s transform loops);
    - profile phone (`profile-phone-in`);
    - secure network: faces, dash, shield, logo, flag entries, plus the SMIL **glint**;
    - protect;
    - invoice (`invoice-doc-in`, rows);
    - orders (`orders-card-in`);
    - agents-ask (typing at 18-32 ms with a caret);
    - tools.
  - Which visual sits in which row is INFERRED from class names. Verify it in the harness before writing parts.
- **Animations that run.** CONFIRMED gpu-props §3.1:

  | animation | where | what it does | runs on | v1 fix (variant) |
  |---|---|---|---|---|
  | four **doc-sweep** gradient titles | CSS 5707/5769/5846/5907/5954/11103, keyframes 5802 | `background-position` on `background-clip:text`, 4 s infinite | main-thread style + paint every frame | sweep-exact G3, or the illusion-sweep proposal |
  | secure-network dash **glint** ×2 | JS 12151-12285 | SMIL `x1/x2` on a `linearGradient` | main thread | glint-ca G1 |
  | cred/profile/invoice entries | CSS 6518, 7519, 8582 | `filter: blur(8px)` with opacity and transform | blur is main thread in Chrome | none: no blur-free identical form |
  | permanent section filter | CSS 5392 | `filter: blur(calc((1-var(--morph-fade))*12px))` on the whole section; `blur(0)` at rest | — | — |
  | stage backgrounds | CSS 6370, 7900-7912 | `blur(16px)`, plus `grain.png` with `mix-blend-mode:overlay` | — | — |
  | vinyl, marquees | — | transform | compositor | none needed |

  At rest, the sweeps plus the glint cost:
  - ULT 120 per 2 s;
  - PrePaint 120 per 2 s;
  - Paint 240-602 per 2 s.

  Pausing both makes y 5346 idle (PP 120 → 5).
- **Dead CSS (do not port).** None of these is referenced by the JS (gpu-props §3.2):
  - `paid-*` (border/rail packets, dissolve, morph, transfer, confetti), CSS 9370-10074;
  - `service-card` transitions, 9214-9367;
  - `quote-*` steps, 8113-8174;
  - `agents-bubble/reply/card/dissolve`, 10147-10256;
  - `secure-ccy/fx` swaps, 6617-6760;
  - `start-selling-to-image`, orbit swap, `carousel-cinema`, `commission-accent-sweep`.
- **v1 cost.**
  - Switching off the end-of-page background pictures cut phone slow frames from a median of 16 to 3 per run (**end-bg** ablation P-137, the method in `OLD/research/element-ablation/README.md`).
  - Re-encoding images did not buy frames (image-size).
  - Six nested size containers amplify typing writes on WebKit (lesson 7).
  - Breakpoints: the sweep titles have an 860-combo variant and a ≥861 variant (CSS ~5672-5960).

### 2.7 P6: Morph panel and end-of-page interaction (CSS 10439-10810, 11328-11485; JS 12688-13250)

- **Mount.** The `dN` IntersectionObserver fires when `#platform` comes within 200 % (JS 13080-13089; y ≈ 1830 on the phone). It **mounts the whole panel inside a scroll frame**:
  - backdrop;
  - 5 `.start-selling-morph-col` columns of about 21 `loading=eager` images, including five 1282² role PNGs, with 16 s up/down marquees (CSS 10592/10600);
  - veil;
  - centre: logo, title, a **second countdown**, CTA stack;
  - roles, footer, grad.

  Cost: a 42-75 ms frame in Chrome 6x, and about 106 ms on the phone at y ≈ 1830-1970. OBSERVED(v1) middle §0, morph-panel-lazy-mount.
- **The value `--morph`** (`OLD/research/morph-var/README.md`):
  - It runs 0..1 and is not tied to scroll position. A wheel or touch push at the end starts a **680 ms rAF tween**, ease-out cubic `1-(1-t)^3` (`ZM` JS 12694-12698), reversible from the current value.
  - It may start only while the platform fills at least 45 % of the viewport with its bottom within 8 px of the viewport bottom.
  - Derived flags: `is-morphing` > 0.001, `is-on-dark` > 0.2, `is-expanded` > 0.92, aria-hidden < 0.35, tabindex > 0.4.
  - `--morph-fade = 1 - min(1, m/0.55)` fades and blurs `#platform` out.
- **CSS readers of `--morph`:**
  - nav `top/width/height` (layout every frame);
  - `color-mix` background, `border-radius`, `backdrop-filter` blur (paint every frame);
  - logo `left` and translate;
  - actions `gap`;
  - Join `max-width/padding/opacity`;
  - panel opacity/blur/scale.
- **Scroll-jack.**
  - `wheel`/`touchmove` listeners `{passive:false, capture:true}` on `window` while `#platform` is within 200 %;
  - `preventDefault()`;
  - pinning with `scrollTo({behavior:'instant'})` (JS 13078).
- **v1 cost.**
  - The end of the page, opening and closing twice in 13 s: 80 slow frames, 41 very slow, longest **584 ms** on the phone.
  - WebKit repaints a resized composited layer completely (CONFIRMED `RemoteLayerBackingStore.mm`).
  - It keeps no layer pool, so layers built in the first open frame cost 6.5-11 ms. Six designs failed the first-open gate (`OLD/research/end-of-page-fresh/README.md` M1).
  - The final g0.0m reached 4 slow frames, 0 very slow, longest 42 ms.
  - The behaviour changed: the menu follows the finger (PR-040), which the user accepted.
- **v1 variants worth porting as variants here:**
  - g0.0b, the original behaviour played by one WAAPI `cubic-bezier` split of the same curve;
  - CM, transforms on a scroll timeline with four scaled corner clippers;
  - g0.0f, two flat GPU fill layers plus a clip for the bar (Safari);
  - g0.0h, closed columns held as a still picture;
  - g0.0i, a clock layer;
  - g0.0k, finger-following with constant glass;
  - the end-of-page-fresh "D1 always-built card" design, never built.

### 2.8 Cross-cutting mechanisms the rewrite must model explicitly

| mechanism | original behaviour | why it matters for v2 |
|---|---|---|
| shared scroll engine | one rAF runs all callbacks, which interleave reads and writes (forced layouts) | the faithful arm needs the same *frame structure*, so the engine is itself a part (`engine.scroll`: `faithful` vs `batched`) |
| scene gate | section-wide IO, `rootMargin:100% 0px`; `[data-start-selling-scene=paused] :where(*){animation-play-state:paused!important; will-change:auto!important}`; `content-visibility:auto` when inactive | the largest phone style record was 29-32 ms (scene-scope); the gate flapped 800×/10 s; it is a part (`engine.scene`) |
| viewport units / sticky / fixed | 28 viewport-unit declarations; 5 sticky/fixed renderers; `--panel-h: calc(100dvh - 40px)` on phones | WebKit relays out every fixed/sticky renderer and restyles every vh/svh/dvh user on each toolbar step (CONFIRMED `LocalFrameView.cpp` l.1951-1964, `StyleScope.cpp` l.885-920 per gpu-props §0.2). Chrome emulation has no toolbar resize, so the parity matrix must include 430×775 and 430×815 |
| reduced motion | 30 CSS blocks + JS checks (2496, 3101, 3681, 4156, 12979…) | every variant must be exact under `reduce` (v1 T2 rule (d)) |
| registered props | `--entered`, `--copy-in`, `--hero-orbit-angle`, `--start-selling-grad-angle` | custom properties are never accelerated in WebKit (`StyleInterpolation.cpp` l.254-264, per gpu-props §2) |
| Svelte reactivity | state writes go straight to the DOM; `set` compares with `===` | React must not route per-frame values through state (§3.4) |

---

## 3. (b) React decomposition: parts, variants, flags, clock

### 3.1 Repo shape (proposal, INFERRED)

```
apps/site/                      # the rewrite (Vite + React 19.3, prerendered HTML like the SSR original)
  src/engine/                   # ScrollEngine, SceneGate, Signals (threshold owners), Clock facade
  src/parts/<part-id>/          # one folder per part
    part.ts                     # registration: id, slot, variants, deps, conflicts, anchors
    faithful/                   # mechanism-faithful port (CSS Module + driver)
    variants/<variant-id>/      # optimized / proposal variants, one folder each
    parity.json                 # anchor map: data-fw id -> original selector(s), computed-style props to compare
  src/registry/                 # resolve(flags, presets) -> ResolvedConfig (pure; mirrored in Lean, see 3.3)
presets/*.json                  # committed presets: original, v1-g00m, ablations...
tools/parity/                   # Playwright harness (§4)
snapshot/ -> gitignored link    # local pinned v1 snapshot (served, never committed; §6)
```

### 3.2 The part contract

```ts
type PartId = 'nav' | 'nav.hitTest' | 'hero.orbit' | 'hero.deck' | 'hero.exit' | 'hero.accent'
  | 'hero.countdown' | 'hero.cta' | 'hero.cue' | 'people.card' | 'people.o' | 'people.deck'
  | 'people.carousel' | 'pain' | 'pain.notes' | 'commission' | 'commission.typing'
  | 'platform.sweep' | 'platform.glint' | 'platform.entries' | 'platform.stageBg' | 'platform.marquee'
  | 'morph.mount' | 'morph.tween' | 'morph.panel' | 'morph.countdown' | 'morph.columns'
  | 'engine.scroll' | 'engine.scene' | 'images';

interface VariantMeta {
  kind: 'faithful' | 'ablation' | 'optimized' | 'proposal';
  parity: 'T0' | 'T1' | 'T2' | 'T3';           // v1 tolerance tiers (§4.5); claimed, then verified
  provenance?: { v1Fix?: string; v1Note?: string }; // e.g. { v1Fix: 'cd-strip', v1Note: 'research/gpu-props §6 G2' }
  engines?: ('blink' | 'webkit')[];             // e.g. Safari-only variants (g0.0f)
  costTags: ('raf' | 'style' | 'layout' | 'paint' | 'composite' | 'decode' | 'memory')[];
}
interface PartDef {
  id: PartId; slot: string; anchors: string[];  // data-fw ids this part owns
  variants: Record<string, { meta: VariantMeta; load: () => Promise<PartImpl> }>;
  requires?: Partial<Record<PartId, string[]>>; // e.g. morph.countdown:'strip' requires hero.countdown:'strip'|'faithful'
  conflicts?: Array<[string, PartId, string]>;  // e.g. platform.sweep:'exact' x 'illusion'
}
```

**Variant kinds.**

- **`faithful`**: a mechanism-faithful port. Same DOM shape, the CSS restated, the same per-frame reads and writes.
- **Ablation variants, generated per part from v1's element-ablation method:**

  | variant | what it does | keeps |
  |---|---|---|
  | `frozen` | drivers stopped; CSS animations paused at a fixed `currentTime` | layout |
  | `static` | the part's resting end state; no animation | layout |
  | `nopaint` | `background-image:none`, `visibility:hidden` on replaced elements, `mix-blend-mode:normal` | boxes, motion, script inputs (the v1 "remove paint, keep layout and motion" rule) |
  | `box` | an empty element with the faithful variant's measured size per viewport | — (debug) |
  | `off` | unmounted | nothing: allowed only when the preset says `"layoutChanging": true` |

  Each ablation must pass v1's **fairness check** (element-ablation §2): boxes equal, script/layout counts equal, only paint/raster lower.
- **`optimized`**: the v1 fixes, re-implemented from their READMEs rather than their patches:
  - countdown: `faces3`, `strip`, `rollCA`, `hiddenSkip`;
  - hero exit: `timeline`;
  - accent: `flip`, `boilCA`;
  - people: `oFlip`, `prepaint`, `instantFlick`;
  - deck: `cqiHeight`;
  - carousel: `st6`;
  - `pain.notes`: `gated`;
  - commission: `readFirst`, `typingChunks`;
  - platform: sweep `exact`, glint `ca`;
  - morph: `waapiExact`, `compositor`, `steadyGlass`, `prebuilt`, `clockLayer`, `keepPhase`;
  - engine: `batched`, `perElementGate`;
  - images: `cap3x`, `cap2x`, `srcset`.
- **`proposal`**: look changes that need the user, such as `instantFlick` or finger-following morph.

### 3.3 Flags and presets: precedence and semantics

- **Sources, highest priority first:**
  1. URL `?fw=part:variant,part:variant`;
  2. `?preset=<id>` (a file in `presets/`, which may `extends` another);
  3. the registry default, which is always `faithful`.

  Other query keys: `clock=real|virtual`, `t0=<ISO>`, `seed=<n>`, `rm=1`.
- **Rules.**
  - Unknown part or variant is an error page, not a fallback.
  - `requires`/`conflicts` violations are errors.
  - The resolved config is sorted, serialised, SHA-256'd, and exposed as `window.__fw.config` plus a `<meta name="fw-config">`. Every capture and trace records that hash.
- **Pure resolver.** The resolver is a pure function `resolve(registry, preset[], query) → Result<ResolvedConfig, Error[]>`. That makes it a good first **Lean 4** target. The properties to prove:
  - totality;
  - determinism;
  - order independence of query pairs;
  - "every resolved config satisfies requires/conflicts";
  - "`extends` chains terminate".

  The TS implementation is then tested against Lean-generated cases (INFERRED; the Lean note owns the method).
- **Other Lean candidates from this page**, where v1 claimed "identical by construction":
  - **cd-strip geometry**: face *k* sits at `(k−v)·h mod 10h`, and the 11th cell covers the 9→0 wrap (gpu-props §4).
  - **sweep-exact**: `A + B = bg·(1−c) + band·c` (gpu-props §6 G3).
  - **glint-ca**: x2 = x1 + 120 in every keyframe, so the gradient only translates.
  - **hero-exit timeline range** equals the JS formula (FINDINGS T12).
  - **morph WAAPI** split of `1-(1-t)^3` into `cubic-bezier(1/3,1,2/3,1)` (design-engineering README rank 4).

  These are exactly the claims that become theorems rather than screenshots.

### 3.4 Runtime rules inside parts (INFERRED, from v1 lessons)

1. **No per-frame value goes through React state or context.** Drivers write to refs, inline styles, or CSS vars through a tiny `Writer`, as Svelte does. React renders structure once, plus discrete state flips such as tab changes or mount gates.
2. **Threshold ownership.** `engine/Signals` owns derived scroll signals (`heroProgress`, `platformNear`, `morphValue`) with exactly one writer each. Parts subscribe to them. The faithful engine reproduces the original's single-frame triple flip at 0.72. An optimized engine may split it.
3. **The faithful engine is literal.** It is one passive listener → one rAF → callbacks in registration order, each performing the original's reads and writes, *including* the forced-layout order.
4. **The DOM shape stays close to the original.** Depth, `display: contents` wrappers and stacking contexts matter, because the costs are structural: layer count, presence flips, size containers.
5. **Prerender.** The original's first paint is SSR, then hydration (`is-preparing` → ready at 1820 ms), so the rewrite is prerendered too. Otherwise load frames and entrance timing differ.
6. **Production build only for measurement.** Dev-mode StrictMode double effects, DevTools hooks and HMR are out.

### 3.5 Deterministic clock and scroll driver

**Principle.** Time is virtualised from *outside*, so the same harness drives the original snapshot and the rewrite with no app cooperation.

| source of time | how it is controlled | status |
|---|---|---|
| `Date`, `setTimeout/Interval`, `requestAnimationFrame`, `requestIdleCallback`, `performance`, `Event.timeStamp` | Playwright `page.clock.install({ time: t0 })` then `pauseAt`/`runFor`/`fastForward` | CONFIRMED playwright.dev/docs/clock (Playwright 1.64.1 on npm, 2026-10-16) |
| CSS animations/transitions, WAAPI | not covered by `page.clock` (the doc lists none); per step: `document.getAnimations().forEach(a => { a.pause(); a.currentTime = tVirtual - a.startTimeOffset })`; finite entrance animations: `finish()` after their end; Chrome extra: CDP `Animation.setPlaybackRate(0)` / `Animation.seekAnimations` | INFERRED from the doc's silence; v1 used `getAnimations()` pause and seek (breakpoints §3.1, cd-strip `pixels.mjs`) |
| SMIL (original glint) | `svg.pauseAnimations()` + `setCurrentTime(t)` | CONFIRMED v1 pixel-tolerance M2 |
| scroll-driven animations | deterministic in scroll position; set scrollY with `behavior:'instant'` (html has `scroll-behavior:smooth`) | CONFIRMED v1 pitfall (breakpoints §3.1) |
| compositor frame (Chromium) | chrome-headless-shell with BeginFrameControl: `HeadlessExperimental.beginFrame({frameTimeTicks, interval, screenshot})`, "designed for use with --run-all-compositor-stages-before-draw" | CONFIRMED devtools-protocol `HeadlessExperimental.pdl`; new for v2 (v1 never used it) |
| randomness | seeded PRNG `mulberry32(seed)` installed over `Math.random` by the harness init script, for both arms | INFERRED |
| countdown target | pin `t0` well before `2026-11-02T12:00+07:00` (e.g. `2026-10-01T00:00:00+07:00`) in every capture of both arms | CONFIRMED need (JS 3905) |

**Scroll driver.** `window.__fw.scroll` exists in the rewrite. For the original, the harness injects an equivalent. It offers:
- `to(y)`, an instant scroll;
- `script(profile)`, which steps scrollY per virtual frame from a committed profile: v1's scripted swipe, a fling, slow drags, and finger replays converted from `OLD/fixes/iphone-wave2/raw/` logs (`[t, dt, scrollY, innerHeight]` frames);
- `toolbar(innerHeight[])`, which replays 775↔815 steps through `setViewportSize`.

One virtual frame is:
1. `clock.runFor(16.667)`;
2. apply the scroll step;
3. seek CSS animations;
4. `beginFrame` (Chromium) or a rAF round-trip (WebKit);
5. capture.

---

## 4. (c) Proving the rewrite is "identical"

### 4.1 Arms and serving

- **A** = the original snapshot, served from the local pin (§6) with `--vendors=local`-equivalent stubs. v1's `tools/serve.mjs` behaviour is the reference.
- **R** = the rewrite at preset `original`, which is all `faithful`.
- **A2** = A loaded again: the A/A noise floor, captured in every run, as v1 required (pixel-tolerance §3 rule (f)).
- Both arms must use the same bytes: images and fonts are served from the same snapshot directory at the same URL paths. Wait for `document.fonts.ready`, `img.decode()` on every visible image, and 2 frames.

### 4.2 Five parity levels, run per part

| level | what | how | gate |
|---|---|---|---|
| L0 structure | the anchor set exists, counts match (e.g. 4 units × 2 digits × faces) | `parity.json` maps each `data-fw` id to an original selector (class names only) | exact |
| L1 boxes | `getBoundingClientRect` (and `getClientRects` for inline titles) of every anchor at each stop | both arms at the same virtual time and scroll | ≤ 0.5 CSS px (≤ 1 device px at DPR 3) |
| L2 computed style | per anchor, a property list from `parity.json` (transform matrix, opacity, filter, font metrics, colours, `will-change`, `position`, `contain`, `container-type`, `content-visibility`) | `getComputedStyle` | exact strings after normalisation; numeric ≤ 1e-3 |
| L3 pixels, still | full frame and per-part crops at fixed stops (top, hero 0.5vh, people, pain, commission, platform rows, end), animations frozen at t | Playwright screenshot or `beginFrame` screenshot; diff by per-channel level | v1 tiers (§4.5) against the same-run A/A |
| L4 pixels, motion | frame sequences at virtual times `t_k = k·16.667 ms` for each animated part (countdown roll, accent cycle, carousel step, reveal 0-1.6 s, morph 0-680 ms, the sweep period 4 s, the glint period 5 s) and for scripted scroll profiles | same as L3, every frame; plus anchor-position paths (v1 M4: path offsets 0.002-0.64 px found only this way) | per frame as L3, plus "motion path within 1 device px at every frame" (T2 (g)) |

Two more gates apply.

**L5, the cost signature (work parity).** This is §4.6.

**Engines.**
- Chromium: Playwright's bundled browser, with `beginFrame` in headless-shell.
- WebKit: Playwright's WebKit on macOS.

Playwright WebKit is not Safari's exact build. Before declaring a part faithful, run a final **Simulator** check at 430×775 DPR 3, using v1's `simvp` approach. v1 found WebKit-only differences: R5 orbit cards, a dash edge of 17, corner squares from bug 312584. INFERRED that Playwright WebKit catches most of them; UNRESOLVED.

### 4.3 Determinism checklist (from v1 pitfalls)

- Pin `Date` before the countdown target. Seed `Math.random`.
- Settle at least 2 s, or `finish()` finite entrances, before freezing. A 1.2 s settle produced false flags from the future-card blur and the nav earn sheen (breakpoints §3.1).
- Pausing an infinite loop shifts its phase (FINDINGS P11). Always seek to an absolute virtual time; never "pause where it is".
- Use `scroll-behavior` instant for every scripted scroll.
- Chrome's `Page.captureScreenshot` made a corner artifact that screencast frames did not (lesson 17). Prefer `beginFrame` screenshots and keep an A/A.
- The hero card photos had a load-dependent "soft vs sharp" raster at 1440 with reduced motion. Cause UNRESOLVED (breakpoints §3.2). Run several loads, compare against the A/A, and do not chase it as a rewrite bug.
- 6 AVIFs were 404 in the first mirror, falling back to bigger PNG/JPEG. Pin S2 fixed this (`OLD/baseline.json` note). The rewrite must reproduce the **same `<picture>` source logic** (`IE()` JS 3475-3486), or images differ.
- The countdown cell `c` comes from an integer `offsetHeight`, which is why the digits land on whole device pixels. Keep the same measuring rule.

### 4.4 Viewport matrix

- **Core.** Every PR runs these configs:
  - 430×932 and 430×775 / 430×815 (toolbar), DPR 3, touch;
  - 375×667 DPR 2;
  - 1440×900 DPR 2;
  - reduced motion at 430 and 1440.
- **Full.** For promoting a part to `faithful`:
  - v1's 14 configs (breakpoints §3): 375, 390, 412@2.625, 430, 600/601, 768t, 860/861, 1000/1001, 1024t/1024, 1280, 1440, 1920;
  - 932×430 landscape, with screen 430×932 so that `device-width ≤ 500` matches;
  - reduced motion.
- **Breakpoint edges.** Live resizes across 400, 600 and 860, because `c` and the JS gates follow them.

### 4.5 Thresholds

Use v1's tolerance report and tiers from `OLD/research/pixel-tolerance/README.md` §3, option B, which v1 recommended:

| tier | rule |
|---|---|
| T0 exact | 0 differing pixels beyond A/A |
| T1 within A/A | every difference at or below what A shows against A2 |
| T2 near-identical | fill ≤ 24 levels, edge ≤ 64, area ≤ 0.1 % of the frame beyond A/A and ≤ 300 CSS px² per element; only anti-aliased edges or sub-pixel phase; reduced motion exact; checked in both engines; paths within 1 device px |
| T3 | needs the user |

- **The five numbers** reported for every diff: max level, % of frame beyond A/A, CSS px², edge-vs-fill share, static-vs-motion.
- **Pixel rule.** A pixel "differs" when any channel moves by more than 8 levels (v1 M3). Report level histograms too, so 1-8 level shifts are visible.
- **Gate for `faithful`.** The `faithful` variant of every part must reach **T1** in Chromium and WebKit at the core matrix, L0-L4. Optimized variants declare their tier, and the harness verifies it.

### 4.6 Cost-signature parity (L5)

Per part, per scenario (rest 6 s at each stop; scripted scroll; part trigger), count in Chromium traces:
- rAF callbacks;
- UpdateLayoutTree / Layout / PrePaint / Paint / RasterTask;
- forced layouts (`Layout` inside a script stack);
- elements restyled;
- composited layer count and memory (Layers domain);
- `getAnimations()` count and which ones are compositor-run (Blink `Animation` trace `compositeFailed`);
- listeners and their passivity.

WebKit gets the same counts from Playwright WebKit and a Simulator Timeline: Layout, RecalculateStyles, Paint, Composite records.

**Gate (INFERRED, numbers to be calibrated in the first wave).** R's counts fall within A's own spread across about 5 loads, with every mechanism present: same layer count ±0, same compositor/main-thread split per animation.

v1 already has census tools to borrow ideas from (`OLD/research/gpu-props/tools/comp-census.mjs`, `OLD/tools/lib/trace-frames.mjs`). Re-implement them; do not copy.

---

## 5. (d) MUI: what it costs and what to do

### 5.1 Status in October 2026

| item | status | source |
|---|---|---|
| Material UI latest | **9.5.0** (2026-10-09); `next` = 10.0.0-alpha.0; `latest-v7` = 7.3.11; no v8 was ever published on npm | CONFIRMED `npm view @mui/material dist-tags/time` |
| v9.0 | stable 2026-04-07 (blog post 2026-04-08): Material UI and MUI X now share the major; "`sx` prop performance improvements up to 30%"; CSS variables generate `color-mix()`; future work: **"Remove dependency on Emotion"** | CONFIRMED https://mui.com/blog/introducing-material-ui-v9/ |
| runtime styling | `@mui/material@9.5.0` peer-depends on `@emotion/react` and `@emotion/styled` (with an optional `@mui/material-pigment-css`) | CONFIRMED `npm view @mui/material@latest peerDependencies` |
| Pigment CSS (zero-runtime) | "remains in alpha phase and is currently on hold … not being developed at the moment" (post of 2026-01-01); `@pigment-css/react` latest 0.0.31 | CONFIRMED https://mui.com/blog/2026-and-beyond/ ; npm |
| CSS layers | `enableCssLayer` (v7, backported to v6) via `StyledEngineProvider`; `modularCssLayers` theme option since 7.2.0 | CONFIRMED https://mui.com/material-ui/customization/css-layers/ |
| Base UI | stable (1.1 in Jan 2026); npm `@base-ui/react` **1.9.0**; unstyled, no CSS-in-JS | CONFIRMED blog post above; npm |

### 5.2 Why MUI would pollute measurements

- **MUI's own animated widgets animate layout.** In MUI 9.5.0 `Tabs`:
  - `updateIndicatorState` reads `getBoundingClientRect`-based `tabMeta`;
  - it sets `left`/`right` and `width` on `TabsIndicator`, which carries `getTransitionStyles(theme)`;
  - tab scrolling is animated by `animate(scrollStart, …)`, a rAF loop writing `scrollLeft`.

  CONFIRMED in `@mui/material@9.5.0/Tabs/Tabs.js` l.180-200, 380-420. This is the "layout property in decoration" pattern v1 removed (lesson 5). `Collapse`, `Accordion` and `Grow` use `react-transition-group` with height or transform transitions (INFERRED; check before use).
- **Emotion injects rules at runtime.**
  - New style objects are serialised and hashed during render, then inserted into a `<style>` sheet. In production that goes through CSSOM `insertRule`.
  - Each insertion is a stylesheet mutation that both engines must invalidate against. INFERRED from Emotion's sheet design; to be measured.
  - Any `sx` value that changes per frame mints a new class per value. That would be catastrophic, and it is banned by §3.4 rule 1 anyway.
- **Parity effort is not reduced.** The original is not Material Design. Every MUI component would need its default styles overridden to match the snapshot, so the visual work lives in CSS either way.

### 5.3 Recommendation (INFERRED, for the user to approve)

1. **Animated and parity-critical parts** (hero, people, pain, commission, platform, morph, nav): React + **CSS Modules** with plain CSS. These restate the snapshot's rules most directly and add zero runtime. No `@mui/*` import under `src/parts/**`, enforced by lint (`no-restricted-imports`).
2. **Interactive behaviour without styling** (signup dialog focus trap, language menu, profile tab semantics): **Base UI**, which is MUI-family, unstyled and zero-runtime, styled with CSS Modules. This honours "use MUI" in spirit without Emotion.
3. **Material UI proper**, if wanted: only for non-animated chrome, such as a debug overlay or flag picker inside the site. Use `enableCssLayer` (layer order `mui` below `parts`), `cssVariables: true`, and Emotion SSR extraction at prerender so no rule is inserted after first paint.
4. **Runtime guard in measurement mode.** Wrap `CSSStyleSheet.prototype.insertRule`/`replace` and observe `<head>` for `<style>` mutations. Any insertion after `__fw.markMeasureStart()` fails the run with `STYLE-INJECTION`.
5. **Make it an experiment, not a confound.** Offer a part variant pair `impl: plain | mui` for one or two simple parts, such as the CTA stack and the tabs chrome. The cost of MUI/Emotion then gets measured like any other variant.

The console tools are a separate app using shadcn/ui (Tailwind v4 plus Radix or Base UI primitives). Its runtime never runs inside measured pages, so it needs no such constraint.

---

## 6. (e) Legal and ethics: keeping Fastwork's property out of git

| item | rule | how (INFERRED unless cited) |
|---|---|---|
| snapshot (HTML/JS/CSS) | never in git; reference only by path, class name and line | v1 precedent: `site/`, `site-pretty/` gitignored since 2026-10-13, pinned by `baseline.json` (`snapshot`, `trees`, `contentHash`) (CONFIRMED `OLD/.gitignore`, `OLD/baseline.json`, OLD CLAUDE.md hard rule 3) |
| images (224 files, 24 MB) and fonts (Google Sans woff2, Playpen Sans, fastwork-Bold.ttf) | never in git, never re-encoded copies in git (an image-cap variant writes into gitignored `out/`, as v1's `build-cap.mjs` did) | the new repo commits a `snapshot.lock.json` (snapshot id + content hash, copied from `OLD/baseline.json`) and a `FW_SNAPSHOT_DIR` env var; a dev/preview server middleware serves `/selling/**`, `/_app/immutable/assets/*.woff2`, `/fonts/**` from that directory; startup refuses on a hash mismatch (`BASELINE-MISMATCH`, v1 semantics). Source of the dir: the local v1 checkout or the v1 GitHub Release file (`npm run init`) |
| text copy and design values in the faithful port | they are Fastwork's expression (headlines, colours, gradient stops, durations, keyframes restated in CSS Modules) | treat `apps/site/src/parts/**` as **Fastwork-derived**: `REUSE.toml` → `LicenseRef-Fastwork-Permission`, as v1 did for quoted lines in `patch.diff` (CONFIRMED `OLD/LICENSING.md`). The permission (`OLD/LICENSES/LicenseRef-Fastwork-Permission.txt`, 12 Oct 2026) covers "this study", and "reusing it outside this study needs Fastwork's own permission" |
| screenshots / diff PNGs / traces | Fastwork pictures: `out/` only (gitignored); committed results hold numbers and hashes only | v1 rule |
| personal data | no emails, LAN IPs, device ids in any committed file; scrub check before the user pushes | v1 hard rules 2 and 12 |
| guardrails | `.gitignore` (`snapshot/`, `out/`, `*.png` under `out/`); a pre-commit hook refusing image/font extensions and any file whose hash appears in the snapshot manifest; Claude deny rules on `git add -f` | port of v1's enforcement (`.githooks/pre-commit`, `.claude/settings.json`) |

**Open legal question for the user.** Does the 12 Oct permission ("publish the link and source according to your study") extend to a public React re-implementation that restates the page's design and copy? Until answered, keep the v2 repo private, or publish only engine, harness and research, with `apps/site` ported content excluded.

---

## 7. Risks

1. **A faithful port may not be cost-faithful.** React reconciliation, effects ordering and a different DOM depth can change style-invalidation scope and layer decisions. The L5 gate exists for this, but some Svelte-specific timing, such as hydration order and effect flush, cannot be identical. Severity: high. It decides whether v2 findings transfer to the real site.
2. **Playwright WebKit is not iOS Safari.** It has no iOS toolbar, no conservative iOS compositing policy (`RenderLayerCompositor.cpp` l.3977+, rdar://71881767 per gpu-props §2), and no `RemoteLayerBackingStore` behaviour on device. Parity "in WebKit" needs a Simulator step.
3. **The countdown target date (2026-11-02) passes during the experiment.** Unpinned captures of either arm will change state.
4. **Size of the port.** About 11.8k lines of page CSS, roughly half of it dead. Platform visual mapping and dead-code pruning must be verified per part, or time goes into porting invisible animations.
5. **MUI expectations.** The user asked for MUI. The evidence says MUI's styled components are a measurement confound, so the recommendation narrows it. This needs explicit sign-off.
6. **Legal scope** of the derived port (§6).
7. **Load-dependent raster states** (soft or sharp photos) and image decode timing can produce A/A noise that looks like rewrite bugs.

## 8. Open questions for the user

1. Material UI only for non-animated chrome, with Base UI and CSS Modules for the site parts: is that acceptable, or must the parts be written with MUI components, accepting the Emotion confound as a measured variable?
2. Does the Fastwork permission cover a (public) React port that restates design values and copy, or should `apps/site` stay private and unpublished?
3. Which v1 build is the "original" for parity: the snapshot `b1789284481295-a455e793` (v0), with v1's g0.0m as a preset only? Recommended: v0 is the parity reference.
4. Is T1 (within A/A) in Chromium and Playwright WebKit enough to call a part `faithful`, or is a Simulator check required per part?
5. Which interaction model is the morph's `faithful` variant? Recommended: the original 680 ms scroll-jacked tween, with v1's finger-following end as a `proposal` variant.

## 9. Sources

**v1 repo (read-only)**
- `OLD/site-pretty/index.html` (SSR structure, l.62-80 bootstrap)
- `OLD/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`: lines cited inline (2663-2780 engine; 3087-3141 commission; 3791-3936 countdown; 3905 target date; 4131-4229 hero; 4409-4740 pain; 10745 profile; 11257 people; 12151-12285 glint; 12414 platform; 12688-13089 morph and nav)
- `OLD/site-pretty/_app/immutable/assets/2.gBuqKVzi.css`: keyframe and class line ranges cited inline
- `OLD/research/01-initial-investigation/motion-inventory.md`
- `OLD/research/gpu-props/README.md` (§0, §2 engine table with Chromium `compositor_animations.cc` and WebKit `KeyframeEffect.cpp`/`GraphicsLayerCA.cpp` citations, §3 audit, §4 countdown, §6 G1-G3)
- `OLD/research/element-ablation/README.md`
- `OLD/research/image-cost/README.md`
- `OLD/research/morph-var/README.md`
- `OLD/research/breakpoints/README.md`
- `OLD/research/end-of-page-fresh/README.md`
- `OLD/research/design-engineering/README.md`, `hero.md`, `middle.md`
- `OLD/research/knowledge-distillation/README.md` (lessons 1-22)
- `OLD/research/pixel-tolerance/README.md` (M1-M5, tiers T0-T3, option B)
- `OLD/fixes/TOPICS.md`, `OLD/fixes/BEST_BUILDS.md`, `OLD/fixes/cd-strip/pixels.mjs` (header: virtual-clock frozen-frame harness)
- `OLD/baseline.json`, `OLD/.gitignore`, `OLD/LICENSING.md`, `OLD/LICENSES/LicenseRef-Fastwork-Permission.txt`, `OLD/CLAUDE.md` (hard rules)

**External**
- MUI, "2026 and beyond" (2026-01-01): https://mui.com/blog/2026-and-beyond/
- MUI, "Material UI v9.0": https://mui.com/blog/introducing-material-ui-v9/ and https://mui.com/blog/introducing-mui-v9/
- MUI CSS layers: https://mui.com/material-ui/customization/css-layers/
- MUI v7 release: https://mui.com/blog/material-ui-v7-is-here/
- npm registry: `@mui/material` dist-tags and times, `@pigment-css/react`, `@base-ui/react`, `react` (queried 2026-10-17)
- MUI 9.5.0 Tabs source: https://cdn.jsdelivr.net/npm/@mui/material@9.5.0/Tabs/Tabs.js (l.180-200, 380-420)
- Playwright Clock: https://playwright.dev/docs/clock
- Chrome DevTools Protocol `HeadlessExperimental.beginFrame`: https://github.com/ChromeDevTools/devtools-protocol/blob/master/pdl/domains/HeadlessExperimental.pdl
- WebKit, "WebKit Features for Safari 26.4" (threaded scroll-driven animations; cited by v1 gpu-props §0.3): https://webkit.org/blog/17862
