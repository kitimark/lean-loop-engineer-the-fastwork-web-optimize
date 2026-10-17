# 11 · Breakpoints, raw list A: every CSS condition in the original

Kickoff research for v2, written 2026-10-17. It is raw input for the merged breakpoint inventory. The user's hard
requirement is that the rewrite supports every breakpoint of the original identically, for every part.

> Personal, educational study of the public homepage https://fastwork.com/ (not affiliated with Fastwork). This note
> gives media conditions, class names and line numbers of the frozen v1 snapshot. It copies no Fastwork code.

**Paths.**
- `OLD/` is `../fastwork-com-web-optimize` (read-only).
- `2:` is `OLD/site-pretty/_app/immutable/assets/2.gBuqKVzi.css`, the page CSS.
- `DH:` is `.../assets/DialogHeader.Qcgwm6ST.css`, `0:` is `.../assets/0.ChGpbVhU.css`, and `app.DTmXyoED.css` has no conditions.
- `html:` is `OLD/site-pretty/index.html`. It has three inline `<style>` blocks at lines 56-58, all on line 58 for the
  conditions. Lines are 1-based in the prettified snapshot.

**Status words.**
- **CONFIRMED** means the snapshot line cited says so.
- **INFERRED** means my reading of the cascade, or a part mapping, that no measurement has checked yet.

**Method.** A tokenizer script walked all four stylesheets and the three inline `<style>` blocks. It skipped comments
and strings, tracked nested blocks and recorded each block's condition, start line, direct style rules, `@keyframes`
and property names. The script is not committed (scratchpad only). A `grep` of `@media|@supports|@container` confirms
the count: 83 + 6 + 1 + 2 = 92 (CONFIRMED).

## 1. Totals

| item | count | status |
|---|---|---|
| conditional blocks | **92** `@media` (91 top level, 1 nested: `2:3249` inside `2:3248`) | CONFIRMED |
| distinct conditions | 30 (the nested one counted as its effective AND) | CONFIRMED |
| style rules inside them | 418 direct rules, plus 5 `@keyframes` (`DH:111` 1, `2:3986` 4) | CONFIRMED |
| per file | `2:` 83 blocks, `DH:` 6, `0:` 1, `html:58` 2, `app` 0 | CONFIRMED |
| `@supports` | **0** | CONFIRMED (grep) |
| `@container` queries | **0**. Three containers exist only for `cq*` units: `.orbit-card` `container-type:inline-size` (2:1600), `.start-selling-platform-stage-visual` `container: built-stage/inline-size` (2:6394), `.start-selling-platform-secure-network-kr-arm` `container-type:size` (2:6975). Units are used at 2:1569 (`--orbit-u` = 100cqw/302), 2:6398 (artboard `scale(100cqw/640px)`), 2:6985-6993 (`hypot()` of cqw/cqh) | CONFIRMED |
| `not` / `only` / `print` / `screen` / `orientation` / `resolution` / `any-pointer` / `any-hover` / `aspect-ratio` / height queries | **0** | CONFIRMED (grep) |
| syntax | all of `2:` uses range syntax (`width<=860px`, `width>600px`); `html:58` uses legacy `max-width:600px` | CONFIRMED |

## 2. Blocks per condition

Rules = direct style rules (a nested block's rules are counted only in the nested row).

| condition | blocks | rules | sites |
|---|---|---|---|
| `(prefers-reduced-motion: reduce)` | 29 | 64 | DialogHeader:438, DialogHeader:590, DialogHeader:637, DialogHeader:711, 2:1167, 2:1376, 2:2127, 2:3614, 2:3900, 2:5150, 2:6324, 2:6500, 2:6641, 2:7174, 2:7547, 2:8169, 2:8615, 2:8725, 2:8864, 2:9144, 2:9229, 2:9361, 2:10090, 2:10246, 2:10812, 2:11288, 2:11599, 2:11766, html:58 |
| `(width<=1030px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)` | 11 | 80 | 2:3271, 2:3684, 2:3786, 2:4290, 2:4378, 2:4514, 2:4612, 2:4770, 2:4940, 2:5055, 2:5133 |
| `(width<=640px)` | 6 | 43 | 2:1133, 2:3586, 2:7803, 2:10888, 2:11274, 2:11564 |
| `(width<=860px)` | 5 | 33 | 2:899, 2:2305, 2:3519, 2:4093, 2:7798 |
| `(prefers-reduced-motion: no-preference)` | 5 | 10 + 5 @keyframes | DialogHeader:111, 2:2299, 2:3986, 2:11081, 2:11530 |
| `(width<=860px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)` | 4 | 43 | 2:3384, 2:3650, 2:5672, 2:10990 |
| `(width<=600px)` | 3 | 15 | 2:2031, 2:5325, 2:11733 |
| `(width<=1200px)` | 3 | 4 | 2:4484, 2:4508, 2:4935 |
| `(width>=861px)` | 2 | 27 | 2:3248, 2:5818 |
| `(width<=720px)` | 2 | 12 | 2:7825, 2:10793 |
| `(width<=1000px)` | 2 | 5 | 2:7753, 2:10651 |
| `(width>600px)` | 2 | 4 | 2:1925, 2:11391 |
| `(width<=1000px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)` | 1 | 33 | 2:916 |
| `(width<=960px)` | 1 | 10 | 2:10836 |
| `(width>=641px) and (width<=1000px)` | 1 | 4 | 2:1106 |
| `(width<=400px)` | 1 | 4 | 2:1489 |
| `(width<=1000px), (hover: none) and (pointer: coarse) and (width<=1200px)` | 1 | 3 | 2:1473 |
| `(width<=1511px) and (width>=601px)` | 1 | 3 | 2:2009 |
| `(width>=861px) and (prefers-reduced-motion: no-preference)` | 1 | 3 | 2:3249 |
| `(width<=480px)` | 1 | 3 | 2:4635 |
| `(width>=861px) and (width<=1000px)` | 1 | 3 | 2:5624 |
| `(width<=461px)` | 1 | 2 | 2:3594 |
| `(width>640px)` | 1 | 2 | 2:11369 |
| `(max-width:600px) [legacy syntax; = width<=600px]` | 1 | 2 | html:58 |
| `(hover: hover)` | 1 | 1 | DialogHeader:537 |
| `(prefers-color-scheme: dark)` | 1 | 1 | 0:250 |
| `(width>=1001px) and (prefers-reduced-motion: no-preference)` | 1 | 1 | 2:226 |
| `(width<=1279px) and (width>=601px)` | 1 | 1 | 2:2026 |
| `(width>=1001px)` | 1 | 1 | 2:5810 |
| `(width<=1100px)` | 1 | 1 | 2:7748 |

The combos are written in the source as comma lists, so they mean OR (CONFIRMED by syntax):
- **C860** = `(width<=860px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)`, 4 blocks;
- **C1000** = the same with 1000 (`2:916`, commission), 1 block;
- **C1030** = the same with 1030 (profile widgets), 11 blocks;
- **C1000-nodw** = `(width<=1000px), (hover: none) and (pointer: coarse) and (width<=1200px)` (`2:1473`, countdown), 1
  block. It is the only combo **without** the `device-width<=500px` clause.

## 3. Edges and bands

**Width edges.** These are the last CSS px of the lower band (CONFIRMED from §2):
400 · 461 · 480 · 600 · 640 · 720 · 860 · 960 · 1000 · 1030 · 1100 · 1200 · 1279 · 1511.
- `device-width`: 500 (in C860/C1000/C1030).
- Touch clause: `(hover:none) and (pointer:coarse)` up to a width of 1200.
- Preferences: `prefers-reduced-motion` reduce/no-preference (35 blocks), `prefers-color-scheme: dark` (1),
  `hover: hover` (1).

**Test widths that cross every CSS edge** (no touch, device-width > 500): 400/401, 461/462, 480/481, 500/501,
600/601, 640/641, 720/721, 860/861, 960/961, 1000/1001, 1030/1031, 1100/1101, 1200/1201, 1279/1280, 1511/1512. The
touch and device-width inputs add: coarse+no-hover at 861-1030 and 1031-1200 against 1201, and device-width ≤ 500
in landscape (for example 932x430 with screen 430x932). Each preference also goes both ways. All INFERRED as a test
plan.

**Sizes that change continuously with width, between the edges.** These are not breakpoints, but a faithful rewrite
must restate them exactly. The knee is where a clamp() reaches its bound (CONFIRMED arithmetic on the cited values):

| site | expression | knees (CSS px wide) | part |
|---|---|---|---|
| 2:1764 | hero h1 font clamp 40 / 4.5vw / 64 | 889, 1422 | hero |
| 2:1777 | `.hero-title` gap clamp 14 / 1.6vw / 24 | 875, 1500 | hero |
| 2:2261 | `.pain-note` padding clamp 12 / 2.6vw / 20 | 462, 769 | pain.notes |
| 2:2289 | `.pain-note p` font clamp 14 / 2.2vw / 20 | 636, 909 | pain.notes |
| 2:2442, 2:5445, 2:5668 | `.start-selling-future-title`, `-platform-title`, `-platform-mission-title` font clamp 36 / 4vw / 48 | 900, 1200 | people.card, platform |
| 2:10894 (inside ≤640) | `.start-selling-platform-title` font clamp 32 / 8vw / 40 | 400, 500 | platform |
| 2:3019-3020 | `.start-selling-profile-shell` height/min-height clamp 743 / 100vh-80 / 820 | **viewport height** 823, 900 | people.deck |
| 2:2026 | `--orbit-edge-push` = max(0, (1280px - 100vw) * 0.35) | 1280 (and 601-1279 gate) | hero.orbit |

Viewport units in the four sheets: `vw` 34, `vh` 15 plain, `svh` 9, `dvh` 7 (grep counts). Height and the iOS
toolbar therefore matter even though no query tests height (CONFIRMED counts; impact INFERRED).

## 4. Traps for "identical at every breakpoint"

1. **The combos are not the complement of the desktop queries (CONFIRMED by syntax; effect INFERRED).**
   - C860 (`2:3384`, `2:5672`, `2:10990`) and `(width>=861px)` (`2:3248`, `2:5818`) **both match** in two cases:
     - touch with no hover at 861-1200 (a 1024 iPad);
     - phone landscape where device-width ≤ 500 and the width is ≥ 861 (932x430).
   - The same holds for C1000 `2:916` with `(width>=1001px) and no-preference` `2:226`, and for C1000 with
     `(width>=1001px)` `2:5810`.
   - The cascade then decides:
     - **People:** C860 `2:3384` comes later than `2:3248`, so the phone deck wins on the properties both set (sticky
       → relative). But `2:3267` `.start-selling-profile-shell:not(.is-active-shell){display:none}` has no
       counterpart in `2:3500`, which sets only z-index/opacity/transform. So at 1024t the inactive shells are
       display:none inside a scroll-snap deck (INFERRED; check at 1024t and 932x430).
     - **Platform:** `2:5818` (≥861) comes **after** `2:5672` (C860), so the desktop row-title rules win on shared
       properties at 1024t.
     - `2:10990` (C860, later still) mostly uses single-class selectors, so `2:5818`'s 3-4-class selectors still
       win (INFERRED from specificity).
   - The v1 README §1 line "a tablet takes the phone path of every combo up to 1200 px" is therefore incomplete: a
     tablet takes **both** paths. v2 must keep the same source order and specificity, or reproduce the mixed result.
2. **Gaps at fractional widths (CONFIRMED by syntax; whether they occur is INFERRED).**
   - `(width<=600px)` (`2:2031`, `2:5325`, `2:11733`, `html:58`) against `(width>=601px)` (`2:2009`, `2:2026`)
     leaves 600 < w < 601 matched by neither. `(width>600px)` (`2:1925`, `2:11391`) does match there.
   - The same gap exists at 860/861 (`2:3248`, `2:5624`, `2:5818`), 640/641 (`2:1106`) and 1000/1001 (`2:226`,
     `2:5810`).
   - Browser zoom or a fractional viewport can produce such widths. v2 should restate each bound exactly (`<=600`
     and `>=601`, not `<601`) to keep the same gaps.
3. **The countdown's combo has no device-width clause (`2:1473`).** In phone landscape on a device with hover (rare)
   the countdown would stay large while the other combos switch. On iOS, hover:none + coarse at ≤ 1200 matches
   anyway (INFERRED).
4. **Plain `width<=1200px` blocks (`2:4484`, `2:4508`, `2:4935`)** apply on desktop at 1031-1200 without touch,
   unlike C1030. That gives a separate band for the profile rail, posts and reviews.
5. **Dark mode is written but neutralised (INFERRED, cascade reading).**
   - `0:250` flips the light/dark toggles on `:where(:root)`.
   - `<html data-theme="light">` (html line 2) and `:where([data-theme="light"])` at `0:258` (same specificity,
     later in source) switch them back.
   - Portalled nodes copy `data-theme` from their ancestors (chunks/D313Dngs.js:883).
   - `2:2597` pins the people-o preview to light.
   - v2 must keep the page light under `prefers-color-scheme: dark`, and must not ship a dark theme by default (an MUI
     `CssVarsProvider` would).
6. **`hover: hover` (`DH:537`).** The sb-button hover tint applies only on devices with hover. JS also reads
   `(hover: none)` (chunks/D313Dngs.js:1176, a tooltip).
7. **The nested query `2:3248` > `2:3249`** gives an effective `(width>=861px) and (prefers-reduced-motion:
   no-preference)` for the profile sticky; the shell rule `2:3267` is gated by width only.
8. **The legacy syntax in inline CSS (`html:58`)**: `max-width:600px` is equivalent to `width<=600px` (CONFIRMED,
   MQ4). The inline `<style>` tags (html 56-58) come after the four `<link>` sheets (html 52-55), so on ties of
   specificity the inline CTA rules win. v2 must keep that order (CONFIRMED order; effect INFERRED).
9. **Reduced motion changes layout as well as animation**:
   - `2:2127` changes the `.hero-track` height;
   - `2:2299` makes pain sticky only when motion is allowed;
   - `2:226` and `2:3249` make commission and profile sticky only when motion is allowed;
   - `2:11766` sets html `scroll-behavior` to auto.
   So reduced motion is a layout axis (CONFIRMED by the property names listed in §5).

## 5. Every block, mapped to parts

Parts follow PLAN §6.1. `ui.shared(sb-*)` = the design-system button, tooltip and spinner used inside overlays and
the nav (no part id yet). `theme.tokens` = global tokens. A part mapping comes from class names (CONFIRMED that the
class is in the rule). The owning part of a Svelte scope with no SSR markup is INFERRED:
- `svelte-y6lofc`, `1egso1f`, `19hdikk`, `9ggcvl`, `1v32ze3`, `157elx8` are profile widgets made client-side (JS
  6504-10608) → `people.deck`;
- `svelte-2l8ken` sits inside the signup `sb-dialog` → `overlays.signup`;
- `svelte-1666oc5` (the countdown) is used by both the hero and the morph panel (JS 3978; morph markup JS 12879) →
  both `hero.countdown` and `morph.countdown`.

| # | site | condition | rules | parts | what it changes |
|---|---|---|---|---|---|
| 1 | DialogHeader.Qcgwm6ST.css:111 | `(prefers-reduced-motion: no-preference)` | 1+1kf | ui.shared(sb-*) | Tooltip entrance animation only when motion is allowed. |
| 2 | DialogHeader.Qcgwm6ST.css:438 | `(prefers-reduced-motion: reduce)` | 1 | ui.shared(sb-*) | Shortens the sb ring/spinner animation under reduced motion. |
| 3 | DialogHeader.Qcgwm6ST.css:537 | `(hover: hover)` | 1 | ui.shared(sb-*) | sb-button hover background only on hover-capable devices (touch gets no hover tint). |
| 4 | DialogHeader.Qcgwm6ST.css:590 | `(prefers-reduced-motion: reduce)` | 1 | ui.shared(sb-*) | sb-button delayed-loading: drops the animation delay under reduced motion. |
| 5 | DialogHeader.Qcgwm6ST.css:637 | `(prefers-reduced-motion: reduce)` | 1 | ui.shared(sb-*) | sb-button transitions off under reduced motion. |
| 6 | DialogHeader.Qcgwm6ST.css:711 | `(prefers-reduced-motion: reduce)` | 1 | overlays.signup | sb-dialog open animation off under reduced motion. |
| 7 | 0.ChGpbVhU.css:250 | `(prefers-color-scheme: dark)` | 1 | theme.tokens | Flips the lightningcss light/dark toggles on :where(:root) / [data-sb-theme=default]. Neutralised on this page: <html data-theme="light"> and the later :where([data-theme=light]) rule (0.ChGpbVhU.css:258, same 0 specificity, later in source) win; portals copy data-theme (chunks/D313Dngs.js:883). INFERRED no visible effect. |
| 8 | 2.gBuqKVzi.css:226 | `(width>=1001px) and (prefers-reduced-motion: no-preference)` | 1 | commission | Desktop-only sticky commission (min-height 100vh+48, sticky top -48). Note: overlaps the 1000-combo at touch 1001-1200 and device-width<=500 landscape (both match). |
| 9 | 2.gBuqKVzi.css:899 | `(width<=860px)` | 4 | overlays.drawer | why-bring drawer: panel moves to bottom sheet style, title text wrap, close button position. |
| 10 | 2.gBuqKVzi.css:916 | `(width<=1000px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)` | 33 | commission | Commission phone/tablet layout: shrink vars reset, sticky off, card radius/padding, single-column rows, compact copy (copy-desktop hidden, copy-compact shown), fee visual scale, underline, why-link. |
| 11 | 2.gBuqKVzi.css:1106 | `(width>=641px) and (width<=1000px)` | 4 | commission | Commission tablet band 641-1000: rows go 2-column grid, divider horizontal. |
| 12 | 2.gBuqKVzi.css:1133 | `(width<=640px)` | 6 | commission, overlays.drawer | Commission title sizes and underline for <=640; why-bring panel becomes full-width bottom sheet with scroll body. |
| 13 | 2.gBuqKVzi.css:1167 | `(prefers-reduced-motion: reduce)` | 9 | pain.notes, commission, commission.typing, overlays.drawer | Reduced motion for pain extra notes and all commission animations (underline frames, fee avatars/messages, typing caret, why-bring). |
| 14 | 2.gBuqKVzi.css:1376 | `(prefers-reduced-motion: reduce)` | 5 | hero.accent | Script accent (hero/start-selling title accent) static under reduced motion. |
| 15 | 2.gBuqKVzi.css:1473 | `(width<=1000px), (hover: none) and (pointer: coarse) and (width<=1200px)` | 3 | hero.countdown, morph.countdown | Countdown units/faces/labels smaller (font 28 per v1 README) at <=1000 or coarse<=1200. NB: no device-width clause, unlike the other combos. |
| 16 | 2.gBuqKVzi.css:1489 | `(width<=400px)` | 4 | hero.countdown, morph.countdown | Countdown smallest size (font 24) at <=400. |
| 17 | 2.gBuqKVzi.css:1925 | `(width>600px)` | 2 | hero.cue | Hero scroll cue: blur/copy-from-ring entrance only on >600; after splash, rest transform. |
| 18 | 2.gBuqKVzi.css:2009 | `(width<=1511px) and (width>=601px)` | 3 | hero.orbit | Orbit stage full width and left/right cards pushed in by --orbit-edge-push for 601-1511. |
| 19 | 2.gBuqKVzi.css:2026 | `(width<=1279px) and (width>=601px)` | 1 | hero.orbit | Sets --orbit-edge-push = max(0, (1280px-100vw)*0.35) for 601-1279 (continuous in vw). |
| 20 | 2.gBuqKVzi.css:2031 | `(width<=600px)` | 13 | hero, hero.exit, hero.orbit, hero.cue, hero.deck | Hero phone layout: orbit hidden/replaced by .mobile-deck (cards a,b,d,e positioned), hero-copy repositioned, h1/title sizes, scroll-cue placement. |
| 21 | 2.gBuqKVzi.css:2127 | `(prefers-reduced-motion: reduce)` | 6 | hero, hero.exit, hero.orbit, hero.cue | Hero reduced motion: track height, no scatter/blur, cards/copy/cta static. |
| 22 | 2.gBuqKVzi.css:2299 | `(prefers-reduced-motion: no-preference)` | 1 | pain | Pain sticky only when motion allowed. |
| 23 | 2.gBuqKVzi.css:2305 | `(width<=860px)` | 10 | pain, pain.notes | Pain phone layout: section backgrounds, inner padding, h2/p type, pain-notes hidden (JS gate at nodes/2.DyWL8TcE.js:6217 mirrors it). |
| 24 | 2.gBuqKVzi.css:3248 | `(width>=861px)` | 1 | people.deck | Desktop profile showcase: hides inactive shells; nested motion block makes sticky + chrome + tabs desktop geometry. Overlaps the 860-combo at touch 861-1200 and device-width<=500 landscape (3384 later in source wins on shared props). |
| 25 | 2.gBuqKVzi.css:3249 | `(width>=861px) > (prefers-reduced-motion: no-preference)` | 3 | people.deck | Profile sticky/chrome/tabs desktop geometry (--profile-scale, sticky top) only with motion allowed and >=861. |
| 26 | 2.gBuqKVzi.css:3271 | `(width<=1030px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)` | 20 | people.deck | Profile widgets compact (crumb/claim hidden, cover, identity, avatar, stats sizes) at the 1030 combo. |
| 27 | 2.gBuqKVzi.css:3384 | `(width<=860px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)` | 15 | people.card, people.deck | People phone/touch: future shrink vars reset, profile sticky off, tabs become a horizontal drag rail, deck becomes x-mandatory scroll-snap of shells, all shells shown. |
| 28 | 2.gBuqKVzi.css:3519 | `(width<=860px)` | 12 | people.card, people.o, people.carousel | People card phone layout: future card min-height/padding, title type/wrap, people-o face size, copy line breaks hidden, community pill. |
| 29 | 2.gBuqKVzi.css:3586 | `(width<=640px)` | 2 | people.card, people.deck | <=640: future shrink radius and profile deck bleed. |
| 30 | 2.gBuqKVzi.css:3594 | `(width<=461px)` | 2 | people.carousel | <=461: community pill stacks (column), proof text wraps. |
| 31 | 2.gBuqKVzi.css:3614 | `(prefers-reduced-motion: reduce)` | 6 | people.card, people.deck, people.o, people.carousel | People reduced motion: no transitions on people-o, faces, shells, avatars; o expanded state static; tabs no transition. |
| 32 | 2.gBuqKVzi.css:3650 | `(width<=860px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)` | 1 | people.card | Re-asserts future shrink scale 1 / radius 0 at the 860 combo. |
| 33 | 2.gBuqKVzi.css:3684 | `(width<=1030px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)` | 1 | people.deck | Profile widget logo smaller at the 1030 combo. |
| 34 | 2.gBuqKVzi.css:3786 | `(width<=1030px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)` | 12 | people.deck | Profile 'about' widget compact type/spacing at the 1030 combo. |
| 35 | 2.gBuqKVzi.css:3900 | `(prefers-reduced-motion: reduce)` | 1 | people.deck | Vinyl record spin off under reduced motion. |
| 36 | 2.gBuqKVzi.css:3986 | `(prefers-reduced-motion: no-preference)` | 5+4kf | overlays.drawer | sb-drawer slide-in per side only when motion allowed. |
| 37 | 2.gBuqKVzi.css:4093 | `(width<=860px)` | 6 | overlays.signup, ui.shared(sb-*) | Signup dialog shell: bar/action footer re-grid, sticky footer, close button area at <=860. |
| 38 | 2.gBuqKVzi.css:4290 | `(width<=1030px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)` | 11 | people.deck | Profile post card compact (radius, cover, byline, title clamp, video/mute) at the 1030 combo. |
| 39 | 2.gBuqKVzi.css:4378 | `(width<=1030px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)` | 1 | people.deck | Profile post meta compact at the 1030 combo. |
| 40 | 2.gBuqKVzi.css:4484 | `(width<=1200px)` | 2 | people.deck | Profile rail thumb/title smaller at <=1200 (plain width, no touch clause). |
| 41 | 2.gBuqKVzi.css:4508 | `(width<=1200px)` | 1 | people.deck | Profile posts grid columns/gap at <=1200. |
| 42 | 2.gBuqKVzi.css:4514 | `(width<=1030px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)` | 4 | people.deck | Profile posts masonry columns, rail layout at the 1030 combo. |
| 43 | 2.gBuqKVzi.css:4612 | `(width<=1030px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)` | 6 | people.deck | Profile review summary compact at the 1030 combo. |
| 44 | 2.gBuqKVzi.css:4635 | `(width<=480px)` | 3 | people.deck | Profile review summary restacks at <=480. |
| 45 | 2.gBuqKVzi.css:4770 | `(width<=1030px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)` | 6 | people.deck | Profile review item compact at the 1030 combo. |
| 46 | 2.gBuqKVzi.css:4935 | `(width<=1200px)` | 1 | people.deck | Profile reviews gap at <=1200. |
| 47 | 2.gBuqKVzi.css:4940 | `(width<=1030px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)` | 12 | people.deck | Profile reviews compact: overview grid, digest, faces, filters become horizontal scroll at the 1030 combo. |
| 48 | 2.gBuqKVzi.css:5055 | `(width<=1030px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)` | 3 | people.deck | Profile gallery grid compact at the 1030 combo. |
| 49 | 2.gBuqKVzi.css:5133 | `(width<=1030px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)` | 4 | people.deck | Profile feed compact (inset, tabs, body) at the 1030 combo. |
| 50 | 2.gBuqKVzi.css:5150 | `(prefers-reduced-motion: reduce)` | 1 | people.deck | Profile feed panel animation off under reduced motion. |
| 51 | 2.gBuqKVzi.css:5325 | `(width<=600px)` | 1 | hero.accent, hero | Start-selling title script accent box size at <=600. |
| 52 | 2.gBuqKVzi.css:5624 | `(width>=861px) and (width<=1000px)` | 3 | platform | Platform card/mission spacing and mission title size for 861-1000. |
| 53 | 2.gBuqKVzi.css:5672 | `(width<=860px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)` | 13 | platform, platform.sweep | Platform phone/touch: mission title, row titles stacked; doc/earn/secure title sweep variant (gradient text, sweep animation) at 28px. |
| 54 | 2.gBuqKVzi.css:5810 | `(width>=1001px)` | 1 | platform | Platform mission title letter-spacing/size at >=1001. |
| 55 | 2.gBuqKVzi.css:5818 | `(width>=861px)` | 26 | platform, platform.sweep | Platform desktop row titles: per-row (document/discovered/payment/relationship) title layout and the >=861 sweep variant. Overlaps 5672 at touch 861-1200 / device-width<=500 landscape; 5818 is later so wins on shared props. |
| 56 | 2.gBuqKVzi.css:6324 | `(prefers-reduced-motion: reduce)` | 1 | platform.entries, platform | Platform row point panel/desc transition off under reduced motion. |
| 57 | 2.gBuqKVzi.css:6500 | `(prefers-reduced-motion: reduce)` | 2 | platform.marquee, platform | Platform credential marquees stopped under reduced motion. |
| 58 | 2.gBuqKVzi.css:6641 | `(prefers-reduced-motion: reduce)` | 1 | platform.marquee, platform | Platform secure currencies track/swap animation off under reduced motion. |
| 59 | 2.gBuqKVzi.css:7174 | `(prefers-reduced-motion: reduce)` | 3 | platform.glint, platform | Platform secure network rings/shield/dash-highlight (glint) static under reduced motion. |
| 60 | 2.gBuqKVzi.css:7547 | `(prefers-reduced-motion: reduce)` | 3 | platform.entries, platform, platform.marquee | Platform profile phone and reviews track static under reduced motion. |
| 61 | 2.gBuqKVzi.css:7748 | `(width<=1100px)` | 1 | platform | Platform tools grid columns at <=1100. |
| 62 | 2.gBuqKVzi.css:7753 | `(width<=1000px)` | 4 | platform, platform.sweep | Platform row copy padding and row-title type/overflow at <=1000. |
| 63 | 2.gBuqKVzi.css:7798 | `(width<=860px)` | 1 | platform | Platform row checks hidden at <=860. |
| 64 | 2.gBuqKVzi.css:7803 | `(width<=640px)` | 4 | platform, platform.stageBg | Platform rows single column (stage above copy), stage aspect at <=640. |
| 65 | 2.gBuqKVzi.css:7825 | `(width<=720px)` | 9 | platform | Platform section padding, shrink radius, card, title size, pain underlay/enter vars, tools grid at <=720. |
| 66 | 2.gBuqKVzi.css:8169 | `(prefers-reduced-motion: reduce)` | 1 | platform.entries, platform | Platform service quote steps static under reduced motion. |
| 67 | 2.gBuqKVzi.css:8615 | `(prefers-reduced-motion: reduce)` | 3 | platform.entries, platform | Platform invoice doc/card entrance static under reduced motion. |
| 68 | 2.gBuqKVzi.css:8725 | `(prefers-reduced-motion: reduce)` | 1 | platform.entries, platform | Platform invoice/orders card entrance static under reduced motion. |
| 69 | 2.gBuqKVzi.css:8864 | `(prefers-reduced-motion: reduce)` | 1 | platform.entries, platform | Platform orders card static under reduced motion. |
| 70 | 2.gBuqKVzi.css:9144 | `(prefers-reduced-motion: reduce)` | 2 | platform.entries, platform.stageBg, platform | Platform agents search typing/caret static under reduced motion. |
| 71 | 2.gBuqKVzi.css:9229 | `(prefers-reduced-motion: reduce)` | 1 | platform.entries, platform.stageBg, platform | Platform service card entrance static under reduced motion. |
| 72 | 2.gBuqKVzi.css:9361 | `(prefers-reduced-motion: reduce)` | 1 | platform.entries, platform | Platform service card animating transitions off under reduced motion. |
| 73 | 2.gBuqKVzi.css:10090 | `(prefers-reduced-motion: reduce)` | 3 | platform.entries, platform | Platform paid trace/packet/transfer/confetti static under reduced motion. |
| 74 | 2.gBuqKVzi.css:10246 | `(prefers-reduced-motion: reduce)` | 2 | platform.entries, platform | Platform agents bubbles/replies entrance static under reduced motion. |
| 75 | 2.gBuqKVzi.css:10651 | `(width<=1000px)` | 1 | morph.panel | Morph title font 36px at <=1000. |
| 76 | 2.gBuqKVzi.css:10793 | `(width<=720px)` | 3 | morph.panel | Morph footer stacks at <=720. |
| 77 | 2.gBuqKVzi.css:10812 | `(prefers-reduced-motion: reduce)` | 2 | morph.panel, morph.tween, nav, morph.columns | Morph pill/panel/nav morph and column track: no transitions/blur under reduced motion. |
| 78 | 2.gBuqKVzi.css:10836 | `(width<=960px)` | 10 | platform, platform.stageBg | Platform header/features/rows tablet layout at <=960 (rows stack, visual aspect). |
| 79 | 2.gBuqKVzi.css:10888 | `(width<=640px)` | 21 | platform, morph.panel, morph.columns | <=640: platform features list, row, h3; morph pill/panel geometry vars (--pill-w/h, --panel-w/h), center, title, footer, backdrop; morph columns 4+ hidden. |
| 80 | 2.gBuqKVzi.css:10990 | `(width<=860px), (device-width<=500px), (hover: none) and (pointer: coarse) and (width<=1200px)` | 14 | commission, people.card, platform, platform.stageBg, platform.sweep, morph.panel, morph.tween, nav | 860-combo: all shrink vars neutralised (future/commission/platform scale 1, radius 0), platform card/stage/artboard resized, row titles inline, sweep ::before hidden; nav + morph --panel-h = 100dvh-40 and --panel-w = 100vw-40. |
| 81 | 2.gBuqKVzi.css:11081 | `(prefers-reduced-motion: no-preference)` | 1 | platform.sweep, platform | Platform title sweep gradient animation only when motion allowed. |
| 82 | 2.gBuqKVzi.css:11274 | `(width<=640px)` | 3 | nav.langMenu | Language switch compact (icon only, no chevron) at <=640. |
| 83 | 2.gBuqKVzi.css:11288 | `(prefers-reduced-motion: reduce)` | 1 | nav.langMenu | Language menu open/close animation off under reduced motion. |
| 84 | 2.gBuqKVzi.css:11369 | `(width>640px)` | 2 | nav | Nav translucent white background on >640 (not on dark, not morphing). |
| 85 | 2.gBuqKVzi.css:11391 | `(width>600px)` | 2 | nav | Nav hero-pill hidden until chrome ready, then fades in on >600. |
| 86 | 2.gBuqKVzi.css:11530 | `(prefers-reduced-motion: no-preference)` | 2 | nav | Nav earn button sheen/unmask animation only when motion allowed. |
| 87 | 2.gBuqKVzi.css:11564 | `(width<=640px)` | 7 | nav, morph.tween | Nav phone geometry at <=640: pill/panel vars, top, bar inset, logo scale, button sizes. |
| 88 | 2.gBuqKVzi.css:11599 | `(prefers-reduced-motion: reduce)` | 2 | nav, morph.tween | Nav transitions/blur off under reduced motion. |
| 89 | 2.gBuqKVzi.css:11733 | `(width<=600px)` | 1 | overlays.signup | Signup content bottom padding at <=600. |
| 90 | 2.gBuqKVzi.css:11766 | `(prefers-reduced-motion: reduce)` | 1 | engine.scroll | html scroll-behavior auto (smooth otherwise) under reduced motion. |
| 91 | index.html:58 | `(max-width:600px)` | 2 | hero, morph.panel | Hero and morph CTA stacks go one column and the RSVP button moves first at <=600 (legacy max-width syntax, inline <style>). |
| 92 | index.html:58 | `(prefers-reduced-motion:reduce)` | 1 | hero, morph.panel | Hero and morph RSVP button border transition off under reduced motion. |

## 6. Not swept here

The JS gates mirror some of these queries:
- `nodes/2.DyWL8TcE.js` 3087-3089 (C1000 split into three `matchMedia` calls), 4157 and 12980 (`max-width: 600px`),
  6217 and 11296 (`max-width: 860px`), 10783 (`min-width: 861px`), 4649-4650 and 10914-10915 (C860 in legacy
  max-width syntax), and the `prefers-reduced-motion` reads (2496, 2919, 3101, 3681, 4156, 4596, 6226, 10780, 10917,
  11295, 11607, 11861, 11995, 12197, 12435, 12979);
- `innerWidth` reads at 4192, 6207-6209 and 10800;
- `chunks/D313Dngs.js` 1176 (`hover: none`).

They belong to the JS sweep (list B). They are listed here only so the merge can line them up with §2.
