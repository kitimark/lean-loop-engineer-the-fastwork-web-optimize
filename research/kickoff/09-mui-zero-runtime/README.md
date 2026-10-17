---
id: 2026-10-17-mui-zero-runtime-synthesis
kind: note
title: "09 · MUI everywhere with zero runtime styling: synthesis and recommendation"
status: review
created: 2026-10-17
updated: 2026-10-17
authors: [agent:plan-architect]
topics: [styling, mui, emotion, pigment, measurement, parity]
engines: [chromium, webkit]
builds: ["npm:@mui/material@9.5.0", "npm:@emotion/*@11.14.x", "npm:@pigment-css/react@0.0.30/0.0.31", "npm:vite@8.3.4", "chromium:fcacb60bd396", "webkit:77db40e2fa70"]
links:
  notes:
    - research/kickoff/09-mui-zero-runtime/01-pigment-and-mui-status.md
    - research/kickoff/09-mui-zero-runtime/02-alternatives.md
    - research/kickoff/09-mui-zero-runtime/03-measurement-impact.md
    - research/kickoff/09-mui-zero-runtime/04-hands-on-spike.md
    - docs/plan/PLAN.md (revision 4: §0, §4.2, §6.5, §6.6, §6.7, R9, R21-R22, Appendix B)
---

# 09 · MUI everywhere with zero runtime styling

This note combines the four 09 notes: `[09.01]` Pigment and MUI status, `[09.02]` alternatives, `[09.03]` the effect
on measurement, and `[09.04]` the hands-on spike. On 2026-10-17 you decided to use **MUI everywhere** in the site. You
also remembered that MUI's CSS-in-JS can be compiled to static CSS. The question here is how to use MUI everywhere
without letting runtime styling distort the engine work counts the experiment depends on. Each fact is cited to one
of the notes, which give the upstream URL, package version or source line.

**Status words.** CONFIRMED means a cited source agrees, or a probe or spike observed it on 2026-10-17. INFERRED means
a design choice or reading that a spike still has to check.

## 0. Recommendation in brief

1. **You remembered correctly.** MUI's compiler is **Pigment CSS**. It turns `styled()`, `css`, `keyframes` and `sx`
   into a static `.css` file at build time, and dynamic values become CSS variables set inline. CONFIRMED [09.01 §0,
   09.04 TL;DR]. **It is not a safe base for this project.** It is alpha 0.0.31 and on hold, and its maintainers say
   they may not resume it. Its Vite plugin declares support only up to Vite 6, and it depends on `@mui/system ^6`.
   Material UI 9.1.0 and later (latest 9.5.0) no longer build with it unless `TouchRipple` is patched. It miscompiled
   a dynamic `sx` value without reporting an error. CONFIRMED [09.01 §1-2, 09.04 builds].
2. **Primary stack: "Emotion AOT" on Material UI 9.5.x.** At build time, every MUI style the site can reach is
   rendered and extracted into one static, linked `mui.[hash].css` inside `@layer mui`. Before hydration, the client
   Emotion cache is told that those styles are already inserted. After that, the engines see only static CSS, like
   the original Svelte site. Emotion's remaining work is JS hashing during React renders, and the part rules keep
   renders out of scroll frames. Our own styling is CSS Modules in `@layer parts`, applied through `className` and
   `slotProps.*.className`. Each step of the mechanism is CONFIRMED in Emotion's source [09.02 §2]. That the whole
   pipeline works is INFERRED until spike **SPK-r** passes (§4).
3. **Two fallbacks, kept apart:**
   - **Per part:** Base UI 1.9.0 + CSS Modules, for any part whose style census cannot be completed or whose
     neutrality checks fail [09.02 §5]. The rest of the site stays on MUI, so the design falls back one part at a time.
   - **Whole site:** Pigment 0.0.30 with Material UI pinned to **9.0.1**, used only if SPK-r fails at the mechanism
     level (for example, class hashes that never match between server and client). MUI 9.0.1 builds with no patches
     with Pigment 0.0.30 on Vite 6.4.4 and with 0.0.31 on Vite 8.3.4 (outside the peer ranges, `--legacy-peer-deps`).
     CONFIRMED [09.01 §2.2, 09.04]. At runtime, 0 `<style>` tags and 0 CSSOM insertions were observed for 9.0.1 +
     0.0.31 in Chrome only [09.01 §2.2], and in Chrome 155 and WebKit 27.2 for Pigment on 7.3.11 and patched 9.5.0
     [09.04]. The exact fallback pair 9.0.1 + 0.0.30 was not run in a browser (bundle grep clean; runtime INFERRED).
     Vite 6.4.4 is inside the plugin's peer range.
4. **One measured A/B is worth keeping:** a build variant `style-engine: aot | runtime | pigment`.
   - `runtime` (plain Emotion SSR, no pre-marking) is the **negative control**. The neutrality gate must catch it.
   - `pigment` is optional and time-boxed to 1 agent-day in M2. It puts a number on what Emotion still costs at load
     and hydration. Its deltas are indicative only, because it runs a different MUI version.
   - Nothing in the site depends on either variant.
5. **The style engine is not the main parity risk. MUI's own behaviour is.** Tab indicators that animate layout,
   transitions that force a reflow when they start, FocusTrap's 50 ms interval, Modal scroll lock, ripples and extra
   wrapper elements stay the same under any style engine. CONFIRMED [09.01 §6, 09.03 §1.3]. Rules S5-S7 and S12 handle
   them.
6. **The planned counts cannot detect styling pollution.** The spike's Chrome traces gave identical
   `UpdateLayoutTree`, `elementCount`, `Layout`, `dirtyObjects` and `Paint` counts for a build that inserted 100 rules
   during the scroll and for one that inserted none. Only the time inside style recalcs differed: about 20-24 ms
   against 8-10 ms. CONFIRMED [09.04 §trace]. The plan therefore adds a **sheet-mutation** count family and the
   neutrality gate N0-N5 [09.03 §2].

## 1. The primary stack in detail (all INFERRED until SPK-r, unless marked)

| Piece | Choice | Source |
|---|---|---|
| Versions (exact pins) | `@mui/material` 9.5.0, `@mui/system` 9.5.0, `@mui/styled-engine` 9.5.0, `@emotion/react` 11.14.0, `@emotion/styled` 11.14.1, `@emotion/cache` 11.14.0, `@emotion/server` 11.11.0, `react`/`react-dom` 19.3.1, `vite` 8.3.4. The MUI and Emotion versions are part of the build ID | npm, CONFIRMED 2026-10-17 [09.01, 09.02, 09.04] |
| Theme | One static theme created at module scope. `cssVariables: true` with `disableStyleSheetGeneration`; the variable sheet is written into the static CSS; one colour scheme (no runtime mode switch, nothing written to `<html>`); unused variables trimmed (MUI's skip option, API INFERRED). If N4 shows too many root custom properties compared with arm A, set `cssVariables: false` | [09.03 S8, N4]; [09.04]: with `cssVariables`, Paper elevation changes go through an inline variable and insert nothing |
| Layers | `@layer reset, mui, parts, flags;` declared first in the static CSS. Extracted MUI rules go in `mui` (the wrap is applied to the extracted file at build), CSS Modules in `parts`, flag overrides in `flags`. **Not** through `StyledEngineProvider enableCssLayer`: in MUI 9.5.0 that provider creates its own client-only cache and `CacheProvider` (`@mui/styled-engine` `StyledEngineProvider.js` l.71-130), which would bypass the pre-marked cache and, on the server, emit inline `<style data-emotion>` tags. The client cache instead copies MUI's 10-line insert wrapper, so a miss still lands in `@layer mui`; class names do not change (the wrapper edits `styles` after hashing). K10 decides whether layers stay | [09.02 §6, §8]; [09.03 S11, §5.2]; rev 4 review (source CONFIRMED) |
| Our styles | CSS Modules only, through `className` and `slotProps.*.className`. No `sx`, no `styled()`, no `css`/`keyframes` from `@mui/*` or `@emotion/*` under `src/parts/**` (lint) | [09.02 §8]; [09.03 S1] |
| Global CSS | No Emotion `<Global>` at runtime (`CssBaseline`, `GlobalStyles`, `enableColorScheme`). The reset is static CSS in `@layer reset` | [09.03 S9]: `<Global>` bypasses `cache.inserted` and moves or flushes tags |
| Build step | A build-only **census route** renders every MUI component the site uses in every state it can reach: open overlays, selected and unselected tabs, disabled states. `renderToString` of the site and census routes with one own `createCache({ key: 'mui' })` passed to `createEmotionServer` (which sets `cache.compat`, so no inline `<style>` is rendered: `@emotion/server@11.11.0` `create-instance/index.js` l.9-12, `@emotion/react@11.14.0` `emotion-element.tsx` l.92), then `extractCriticalToChunks` writes `mui.[hash].css` and `emotion-ids.json`. It keeps only ids found in the HTML, and MUI `Portal` renders nothing on the server (`Portal/Portal.js` l.41-66), so the census renders overlays with `disablePortal`, closed (`keepMounted`) and open. The prerendered HTML contains **no** `<style data-emotion>` tags, so the cache has nothing to move when hydration starts | [09.02 §2 (b+)]; [09.03 §1.3] (tag moves); rev 4 review (source CONFIRMED) |
| Client | Create the cache with the same key and stylis config, pass it through `CacheProvider` (no `StyledEngineProvider`), set `cache.inserted[id] = true` for every census id, then `hydrateRoot` | [09.02 §2]: `insertStyles` inserts only when `cache.inserted[name] === undefined` (`@emotion/utils@1.4.2` l.54), CONFIRMED |
| Measurement builds | Wrap `cache.insert` and report every miss to the harness. A miss means the census is incomplete, and the build fails | [09.02 §8]; [09.03 N5] |
| Overrides of MUI behaviour | Ripples off for the whole theme. Built-in Tabs indicator hidden, with the original's indicator drawn in CSS; MUI `Tabs` still reads rects after every render and on every resize (`Tabs/Tabs.js` l.338-381, l.561-611, l.644-646 @9.5.0), so parts on scroll paths use `Tab`s in a plain tablist. Avatar gets its `<img>` as a child, not `src` (`useLoaded`: off-DOM `Image`, two commits per mount, `Avatar/Avatar.js` l.115-145). Transition components replaced on overlays through `slots.transition` by class-toggled keyframes copied from the original's values. No `useScrollTrigger`, no `useMediaQuery` for looks. Overlays mounted at load or kept mounted | [09.03 S5-S7, S10, S12]; [09.02 §9] |

**What the AOT build still costs (INFERRED; measured by the `style-engine` A/B).** In the spike, Emotion builds had
about +16 ms of script at load, about +2 MB of JS heap and about +27 kB of gzipped JS compared with Pigment, and
Emotion serialises styles on every styled render. CONFIRMED [09.04]: one Mac and 3 runs, so these figures are
directional. All of this falls in the load and hydration window, which is outside W-measure but inside the PL6
whole-page check ("rest 6 s + first scroll"). So `markMeasureStart()` must wait until hydration has settled
(`__fw.hydrated`).

## 2. Evidence from the spike and probes

**Build matrix** (CONFIRMED [09.01 §2.2, 09.04 builds]):

| MUI | Pigment | Vite | Result |
|---|---|---|---|
| 9.5.0 | 0.0.31 or 0.0.30 | 8.3.4 or 6.4.4 | **fails**: `TouchRipple.mjs: This identifier cannot be used in the template, because it is a function parameter`. Introduced in 9.1.0 by PR #48357 (reduced motion) |
| 9.5.0 + 1-file patch | 0.0.31 | 6.4.4 | builds and runs; the ripple loses its reduced-motion handling |
| 9.0.1 | 0.0.30 with 6.4.4 [09.04]; 0.0.31 with 8.3.4, `--legacy-peer-deps` [09.01] | see Pigment column | builds with no patch; runtime checked only for 0.0.31, in Chrome only |
| 7.3.11 | 0.0.30 | 6.4.4 (8.3.4 with `--legacy-peer-deps`) | builds and runs with no patch |
| 9.5.0 Emotion | — | 8.3.4 | builds in 0.13 s, against about 3.2 s for Pigment (about 25× slower) |

**CSSOM insertions per phase** (Chrome 155, 3 runs, and WebKit 27.2, 2 runs; identical in both engines with zero
variance; CONFIRMED [09.04]):

| Build | insertRule at load | scroll | tabs | dialog | hover |
|---|---|---|---|---|---|
| Pigment (MUI 7.3.11 or 9.5.0 patched) | 0 | 0 | 0 | 0 | 0 |
| Emotion, dynamic `sx` value ("naive") | 84-90 | **100** | 13-16 | 27-31 | 0 |
| Emotion, dynamic values through CSS variables | 90 | **0** | 13 | 31 | 0 |

Takeaways:
- With the CSS-variable discipline, even plain runtime Emotion inserts nothing **during scroll**. What it still
  inserts is lazy first-mount styles: tab states, Dialog, Backdrop. The census in Emotion AOT is there to close that
  gap.
- Pigment's silent miscompile is real. `sx={{ width: `${p}%` }}` built with exit code 0, emitted `width:null%`, and
  the hook that computed `p` was tree-shaken away. Build gate: fail on `null`, `undefined` or `NaN` values in the
  emitted CSS, whichever engine is used [09.04 errors §5].
- Traces of the scroll phase (168 frames) gave the same counts for all builds: `UpdateLayoutTree` 179,
  `elementCount` 218, `Layout` 168, `dirtyObjects` 336, `Paint` 323. Only the duration changed [09.04].
- Even the CSS-variable Emotion build (`emotion-v7cv`, **0** insertions during scroll) spent 13.2-14.6 ms in
  `UpdateLayoutTree` against Pigment's 7.9-10.0 ms in traces, while CDP `RecalcStyleDuration` showed no gap
  (16-20 vs 16-19 ms). 2-3 runs, unexplained [09.04]. So 0 sheet mutations does not yet prove equal style cost;
  SPK-r records the trace duration for `aot` vs `runtime` (rev 4 review).

**Engine source** (CONFIRMED paths, INFERRED cost [09.03 §1]):
- **WebKit.** One `insertRule` into an active sheet calls `clearResolver()` and then `scheduleFullStyleRebuild()`
  (`StyleScope.cpp` l.585-619, l.726-760; `StyleInvalidator.cpp` l.654-664 @77db40e2fa70). Before WKTR, the WebKit
  counts lane has no element counts, so it cannot see this rebuild.
- **Blink, plain rule.** The cheap diff path, which still rebuilds the sheet's RuleSet and drops the
  matched-properties cache.
- **Blink, `@layer` rule** (every Emotion rule under `enableCssLayer`). A check of every element, a rebuild of all
  at-rule registries (`kRuleSetFlagsAll`), and a font-update restyle and layout invalidation over the whole document
  (`style_engine.cc` l.152-200, l.3171-3325, l.1410-1454 @fcacb60bd396).
- **The original (arm A)** has 4 linked stylesheets and 3 inline `<style>` blocks, and **no** stylesheet API call in
  any JS chunk (local grep). So its expected sheet-mutation count after load is 0.

## 3. How the notes disagree, and the resolution

| Topic | Notes | Resolution | Why |
|---|---|---|---|
| Primary engine | [09.04]: Pigment with MUI 7.3.11 and Vite 6.4.4. [09.01], [09.02], [09.03]: Emotion, made static | **Emotion AOT on 9.5.x is the primary; Pigment on 9.0.1 is the whole-site fallback and an optional measured arm** | Pigment ties us to a paused alpha, to an older MUI (7.3.11 is the previous major; 9.0.1 misses the FocusTrap tab-order fix #48546, the stuck exit transitions fix #48881 and the LazyRipple leak fix #49000), and to Vite 6. If AOT passes SPK-r, the engines see the same static CSS either way. The difference is only load-time JS, and the A/B measures it |
| `cssVariables` | [09.01]/[09.02] on; [09.03] prefers off or trimmed (to keep root custom properties near arm A) | On, trimmed, emitted statically; N4 decides | [09.04] shows on avoids insertions when elevation changes; N4 guards the page-factor bias |
| `impl: plain \| mui` pair | [09.02]: keep it; [09.03]: on every experiment part | Kept as a control twin on **experiment parts only** (thin; it shares the CSS Module and drivers) | N3 needs it to separate MUI's own cost from differences introduced by the port |
| Pigment smoke test | [09.02]: half a day, optional; [09.01]: 1 agent-day measured variant | Its own spike, SPK-s (1 agent-day, M2, optional) | It is a measurement, not a dependency |

## 4. Measurement rules (what the plan adopts)

- **New count family, "sheet mutations"** (PLAN §4.2), counted in every counts-lane run:
  - page side (N0): wrappers on the CSSOM write APIs, plus a `MutationObserver` for `<style>`/`<link>` adds, moves,
    removals and text edits anywhere in the tree;
  - engine side (N1): Chromium `StyleEngine::updateActiveStyleSheets`, `scheduleInvalidationsForRuleSets` and
    font-update slices; WebKit `CSS.styleSheet*` events in attribution runs.

  This replaces and widens the old `STYLE-INJECTION` guard, which wrapped only `insertRule`/`replace` and watched
  only `<head>` [09.03 §2].
- **Neutrality gate N0-N5** (PLAN §6.7):
  - **N0/N1:** 0 sheet mutations in W-rest, W-measure and W-trigger.
  - **N2:** a DOM-write census and a React-commit count per frame (a `<Profiler>` counter, [09.01 §7]) exactly
    equal to `impl: plain`.
  - **N3:** work counts equal to `impl: plain`, with an allowance for MUI's wrapper elements.
  - **N4:** a static style-shape census within ±10 % of arm A.
  - **N5:** at hydration, 0 attribute diffs, 0 cache misses and 0 style-tag moves.

  A failed N0, N1 or N5 is an incident against the part, never a result. A failed N3 makes the part
  `faithful-with-delta`.
- **Styling rules S1-S13** (PLAN §6.5), in short:
  - static MUI styling only;
  - enumerable theme variants;
  - per-frame motion only through MotionClock;
  - state flips map to classes that already exist;
  - no MUI transitions on scroll paths;
  - ripples off;
  - no measuring widgets on scroll paths;
  - one static theme;
  - no `<Global>`;
  - no JS media queries for looks;
  - fixed Emotion configuration in the build ID;
  - overlays mounted and closed during scroll;
  - the original's fonts.
- **Build gates** for every build:
  - the census test (0 misses);
  - no `<style data-emotion>` in the prerendered HTML;
  - no `null`, `undefined` or `NaN` values in the emitted CSS;
  - for the `pigment` variant, no `data-emotion`, `insertRule` or `stylis` in the built JS [09.04 rec. 2].
- **Windows.** `markMeasureStart()` comes after `__fw.hydrated`. Load and hydration costs belong to W-load and are
  judged as class X, never inside W-measure.
- **K10 "sheet mutation" calibration fixture** (M3, in the WKTR spike window, plus about 2 minutes of phone time).
  It prices one insertion per frame (plain, layered, keyframes, appended tag, moved tag, growing sheet) in both
  engines. Its result decides whether MUI rules stay in `@layer mui` [09.03 §5.2].
- **SPK-q:** N0/N1 on arm A in M1, which should read 0. **SPK-r (Emotion AOT):** Button, Dialog, Menu, Tabs and Drawer
  in the harness. Pass means:
  - 0 insertions and 0 tag moves after hydration, in Chromium and WebKit;
  - nothing inserted when each overlay opens;
  - closed-overlay scroll counts equal for `impl: plain` and `impl: mui`;
  - N5 green.
- **Every MUI version bump re-runs N0-N5 on all parts.** A minor release can add a lazily mounted styled child, as
  the ripple did [09.03 §6].

## 5. Open risks

1. **The Emotion AOT pipeline is unproven as a whole.** Possible failures:
   - class hashes that differ between server and client (because of theme or code differences);
   - states the census cannot reach;
   - Popper positioning styles;
   - hydration attribute mismatches that production React does not patch.

   SPK-r tests these. If it fails at the mechanism level, the site moves to the Pigment fallback, with Vite 6.4.4 and
   MUI 9.0.1 pinned (INFERRED).
2. **Pigment as a fallback carries its own risks:**
   - paused alpha;
   - a likely regression on any MUI upgrade (MUI no longer tests v9 against Pigment, INFERRED [09.04]);
   - components outside the probe untested (Select fails under Pigment, material-ui #46592);
   - no dev server or HMR probe, no prerender probe, no `@layer` support;
   - a build about 25× slower.
3. **All cost magnitudes come from source reading.** Until K10 runs, they are not measured. The WebKit counts lane
   cannot see full style rebuilds until WKTR exists (M3). Until then, any MUI diff that affects styling is ranks-only
   at best (PLAN Q10).
4. **MUI's behaviour and DOM depth:**
   - wrappers (Paper, Backdrop, Portal) move PL0/PL1 and PL5 element counts;
   - FocusTrap runs a 50 ms interval while a modal is open, outside `MotionClock`;
   - Modal scroll lock causes a relayout.

   Mitigations: the wrapper map in `parity.json`, the N3 allowance, and the modal scenario measured on its own with
   the interval as a declared exception.
5. **Static shape differences** (rule count, `--mui-*` variables, layers) change per-element style cost without
   changing any count. N4 and PL6 must catch them, otherwise a `ρ_page` fitted on arm A will be biased when applied
   to the rewrite.
6. **MUI may change course during the project.** Draft PRs #48652, #48745, #49001 and #49157 move toward CSS Modules
   and a static theme; none is merged, and v10.0.0-alpha.0 changes nothing here. If one lands, it may beat Emotion
   AOT. Re-check the v10 pre-releases monthly; a scripted `npm view` check is enough, with no agent polling.
7. **Unverified details:**
   - MUI's API for skipping CSS variables;
   - the cost of the `blink_style` trace category;
   - whether the iwdp CSS domain perturbs timing;
   - (resolved in the rev 4 review: the AOT build does not use `enableCssLayer`; see §1 Layers.)
8. **What the gate cannot see** (rev 4 review): Emotion's per-render JS (serialise + hash) and the per-element
   style cost of a larger or differently shaped style sheet. N4 is a proxy and PL6 the final check; a deterministic
   count for the second would be Chromium's CSS selector stats ("Match Attempts", https://developer.chrome.com/docs/devtools/performance/selector-stats;
   trace event name and category INFERRED).

## Sources

The four notes in this folder hold every URL, version and source line. The main ones:
- Pigment repo and discussion #424: https://github.com/mui/pigment-css/discussions/424
- MUI's Pigment migration guide: https://mui.com/material-ui/migration/migrating-to-pigment-css/
- MUI blogs: https://mui.com/blog/2026-and-beyond/ and https://mui.com/blog/introducing-material-ui-v9/
- MUI CSS layers: https://mui.com/material-ui/customization/css-layers/
- MUI CSS theme variables: https://mui.com/material-ui/customization/css-theme-variables/overview/
- Draft PRs: https://github.com/mui/material-ui/pull/48652, /48745, /49001, /49157
- Emotion source at pinned versions: `@emotion/cache@11.14.0` `src/index.ts` l.62-115, l.252;
  `@emotion/react@11.14.0` `src/global.tsx` l.89-138; `@emotion/sheet@1.4.0` `src/index.ts`
- Engine source at the plan's pins: Chromium `fcacb60bd396`, WebKit `77db40e2fa70` (paths in [09.03])
- The spike's scratch apps and `measure.mjs`/`trace.mjs` live in the session scratchpad, not in the repo [09.04]
