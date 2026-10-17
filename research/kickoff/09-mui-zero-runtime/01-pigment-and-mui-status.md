# 09-01 · Pigment CSS and Material UI zero-runtime status (2026-10-17)

Kickoff research note for v2 after the user's decision "MUI everywhere" (2026-10-17). It answers: can MUI's
CSS-in-JS be compiled to static CSS today, at what maturity, with which versions, and what runtime JS remains anyway.
Design input for the plan architect (PLAN rev 3 §6.5 rule 6, Q4, R9). Not a plan.

**Status words.** **CONFIRMED** = a cited source (npm registry, GitHub API, docs, package source) or a probe I ran
today agrees. **INFERRED** = my reading, not checked. Probe = small throwaway builds in my scratchpad (§2.1); they are
evidence for these exact versions only.

---

## 0. Answer in brief

1. **Yes, the user's memory is right in principle.** MUI built exactly that: **Pigment CSS** compiles `styled()`, `css`,
   `keyframes` and the `sx` prop at build time (via wyw-in-js, the Linaria engine) into a static `.css` file plus class
   names. Dynamic values become CSS custom properties set through inline `style`. CONFIRMED (Pigment README; my probe).
2. **But Pigment is paused, alpha, and has fallen behind Material UI.**
   - `@pigment-css/*` latest is **0.0.31 (2026-05-22)**; before that 0.0.30 (2025-01-14). Repo description: "Alpha phase,
     currently, on hold". CONFIRMED (`gh release list`, `gh repo view`).
   - Maintainer status post (2026-06-08): work paused since Jan 2025 because it "slows down the build too much" and "has
     too many bugs"; "with AI, there might not be any need for it now. Tailwind CSS and CSS Modules are progressively
     taking over"; "we don't have a lot of bandwidth for a reset". CONFIRMED (mui/pigment-css discussion #424).
   - **It no longer builds with current Material UI.** My probe: Pigment 0.0.31 + `@mui/material@9.5.0` fails in
     `ButtonBase/TouchRipple` (Vite 8.3.4 and Vite 6.4.4 alike). The breaking code arrived in **9.1.0** (reduced-motion
     support). The same app **builds and runs** with `@mui/material@9.0.1` and `7.3.11`. CONFIRMED (probe §2).
3. **MUI's real forward path is not Pigment. It is "remove Emotion" via plain CSS / CSS Modules + CSS variables.** The
   v9 blog lists "Remove dependency on Emotion" under "What's next". Three draft PoC PRs (Jun–Sep 2026) move component
   styles to CSS Modules, a build-time `theme.css`, cascade layers, and an "unstyled logic / styled shell" split. None is
   merged; v10.0.0-alpha.0 (2026-10-12) ships no styling-engine change. CONFIRMED (§4).
4. **With Emotion (the supported path), the scroll cost can still be near zero if nothing re-renders during scroll.**
   Emotion's cost is at render time (serialize + hash + `insertRule` for new class names). My probe on MUI 9.5.0 +
   `cssVariables`: 41 rules at load, **+11 `insertRule` calls** on "open dialog + change one `sx` width"; the `sx` width
   became a new class per value. Pigment probe, same interactions: **0** inserts, width via `--var` inline. CONFIRMED.
5. **Runtime JS stays either way:** component logic, transitions (forced reflow on enter), FocusTrap (50 ms
   `setInterval` while open), Popover/Popper positioning (rect reads, scroll/resize listeners), ripple, Tabs
   indicator (`left`/`width` inline after rect reads, also under Pigment). CONFIRMED (MUI 9.5.0 source; probe).
6. **Recommendation (INFERRED):** keep Emotion on MUI 9.5.x as the default engine, made "static at scroll time"
   (prerender extraction, `cssVariables`, `enableCssLayer`, no per-frame `sx`, `STYLE-INJECTION` guard), and run
   **Pigment-on-MUI-9.0.1** only as a time-boxed measured variant `style-engine: emotion | pigment`, not as the
   foundation. Details §7.

---

## 1. Pigment CSS: state of the project

| Item | Value | Status |
|---|---|---|
| Packages | `@pigment-css/react`, `@pigment-css/vite-plugin`, `@pigment-css/nextjs-plugin`, `@pigment-css/unplugin`, `@pigment-css/theme`; all `latest` = **0.0.31** | CONFIRMED `npm view` |
| Release history | 0.0.31 2026-05-22 (wyw bump, Next.js 16 peer, Grid proptype); 0.0.30 2025-01-14; 0.0.22–0.0.29 Sep–Dec 2024 | CONFIRMED `gh release list -R mui/pigment-css` |
| Master commits since 0.0.30 | Mostly org-wide infra normalisation by one maintainer; last master commit 2026-06-06 "[internal] Normalization between repositories" | CONFIRMED GitHub API commits |
| Open issues / PRs | 128 / 19 | CONFIRMED GitHub search API |
| Repo description | "Alpha phase, currently, on hold." | CONFIRMED `gh repo view` |
| Official status | Blog 2026-01-01: "Pigment CSS remains in alpha phase and is currently on hold." Discussion #424 (2026-06-08): paused since Jan 2025; 14+ months at 1.5 FTE; would need ~3 FTE and a redesign; "with AI, there might not be any need for it now" | CONFIRMED |
| Earlier pause note | 2025-05-22, maintainer: "paused … short on people … focussed on looking at alternate ways (mainly runtime …) to have a styling engine with RSC support" (pigment-css #388) | CONFIRMED |
| Root problems (MUI's own list, 2025-03-31) | (1) build too slow (MUI store migration abandoned); (2) Next.js/Vite integration unstable, hard to debug; (3) no story for bundlers without a plugin | CONFIRMED material-ui #45759 |
| "v1" rewrite | New framework-independent API (`pigment-core`, PR #367/#371) was "not compatible with `@mui/material`"; never released | CONFIRMED pigment-css #388, #371 |
| Peer ranges (0.0.31) | react `^17‖^18‖^19`; vite-plugin `vite ^4‖^5‖^6` (**no 7/8**); nextjs-plugin `next ^12…^16` | CONFIRMED `npm view … peerDependencies` |
| Hidden deps | `@pigment-css/react` depends on `@emotion/*` (css, react, styled, serialize, is-prop-valid), **`@mui/system ^6`**, `@wyw-in-js/transform ^1.1` (wyw latest is 2.6.0), Babel 7 | CONFIRMED `npm view` |
| Material bridge | `@mui/material-pigment-css` is still published in lockstep (9.5.0, 10.0.0-alpha.0), peer `@pigment-css/react ^0.0.30‖^0.0.31`; it only re-exports Pigment plus `Box`, `Container`, `Grid`, `Stack`, `RtlProvider` | CONFIRMED npm pack 9.5.0 |
| Open blockers of note | Turbopack unsupported (#6); Next 16 App Router node-builtins error (#418); wyw exceptions crash Next (#268); Vite CJS-API deprecation (#67/#409); Vite lib mode (#324); Windows (#385); MUI Select fails to compile with Next ≥15.4 (material-ui #46592) | CONFIRMED issue titles |

**Verdict:** paused, not archived. Not deprecated in the docs (the migration guide still says "early alpha"), but MUI
does not recommend it as the path forward. CONFIRMED.

---

## 2. Probe: does Pigment work with our stack today?

### 2.1 Setup

Minimal Vite app: React 19.3.1, `@vitejs/plugin-react` 6.1.2, Pigment 0.0.31 with
`pigment({ theme: createTheme({ cssVariables: true, … }), transformLibraries: ['@mui/material'] })`, as in the MUI
migration guide. Content: Pigment `Box` + `sx`, a `styled('div')` with `theme.vars` and `variants`, a plain `<div sx>`
with a **state-driven width**, `Typography`, contained `Button`, `Tabs`, `Dialog`, `Drawer`, `Menu`. Installed with
`--legacy-peer-deps --ignore-scripts` (npm), plus one pnpm 10.34.5 rerun. Runtime checked in headless Chrome
(chrome-devtools MCP): rule counts, an `insertRule` hook and a `<style>` MutationObserver, then dialog open, width
change and tab switch.

### 2.2 Results (all CONFIRMED by the probe)

| MUI | Vite | Build | Notes |
|---|---|---|---|
| 9.5.0 | 8.3.4 | **fails** | `TouchRipple.mjs: This identifier cannot be used in the template, because it is a function parameter` (`function getAnimationStyles(theme) { … css\`…\` }`) |
| 9.5.0 | 6.4.4 | **fails** | same error, so it is MUI-version-specific, not Vite-specific |
| 9.0.1 | 8.3.4 | builds 3.2 s; runs | JS 847 kB raw / 171 kB gz; CSS 35.7 kB; 0 Emotion runtime symbols |
| 9.0.1 | 8.3.4 (pnpm 10.34.5) | builds 3.2 s | MUI docs warn of a "known issue with pnpm"; not hit in this single-package probe |
| 7.3.11 | 8.3.4 | builds 4.0 s | JS 826 kB / 165 kB gz |
| Emotion baseline 9.5.0 | 8.3.4 | builds **0.13 s** | JS 1,030 kB / 214 kB gz (different MUI major from the Pigment rows, so size deltas are indicative only) |

- The breaking `getAnimationStyles(theme)` exists in 9.1.0's TouchRipple and not in 9.0.1's. **9.0.1 (2026-05-07) is
  the last Material UI release that builds with Pigment 0.0.31.** CONFIRMED for TouchRipple only. Other 9.x components
  outside the probe may break too (INFERRED; not tested).
- Vite 8 (Rolldown) accepted the plugin despite the `^4‖^5‖^6` peer range. The Pigment transform took ~99 % of build
  time (Rolldown plugin timings). That is ~25× slower than the Emotion build for a 600-module app, in line with MUI's
  "build too slow" (1).
- Runtime, Pigment + 9.0.1: one stylesheet, 259 rules at load, **0 `insertRule` calls and 0 `<style>` added** across
  dialog open, width change and tab switch. Dynamic `sx` rendered as `class="s18y7q4k" style="--s18y7q4k-0: 130px"`.
  The dialog opened and the theme colour applied (`rgb(30,110,255)`). The only console error was a 404 for the missing favicon.
- Runtime, Emotion + 9.5.0 (`cssVariables: true`): 2 `<style data-emotion>` tags, 41 rules at load, then **+11
  `insertRule`** for dialog open plus one width change. The `sx` width became a new class (`css-6lw27z`) with no
  inline style, so every distinct value inserts a new rule.
- Bundle composition, Pigment + 7.3.11: `@emotion/is-prop-valid` + `@emotion/memoize` (prop filtering only), 3 Pigment
  runtime modules (`styled` wrapper, `sx` class/var merger), 4 `@mui/system` modules (breakpoints, colour utils,
  `RtlProvider`, `DefaultPropsProvider`), 6 `react-transition-group` modules.
- Not tested: `vite dev`/HMR, prerender/SSR, WebKit, the full set of MUI components the site will use.

---

## 3. What Pigment compiles, and the limits

From the Pigment README and the Material UI migration guide (CONFIRMED, quoted or closely paraphrased):

- **`sx` prop:** replaced at build time by `className` and `style` props on any JSX element, including plain HTML.
  Accepted forms: plain object (fastest), `(theme) => object`, or an array of those with conditionals. Values that
  depend on runtime variables go through CSS variables in inline style (the probe shows the plugin doing this
  automatically for `width: w`). Custom components must forward `className` and `style`.
- **`styled()`:** "You never get direct access to props in your styled declarations." Prop-based styling goes through
  `variants` (static objects, not callbacks), or a per-property callback that Pigment turns into a CSS variable plus
  inline style. "Pigment CSS will throw an error for styles that depend on a state." Theme `styleOverrides` with
  `ownerState` callbacks are unsupported; use `variants`.
- **Theme:** passed to the bundler plugin. It "is used at build time and does not exist in the final JavaScript
  bundle". With MUI it is `createTheme({ cssVariables: true })`. Standalone Pigment uses `extendTheme`, `colorSchemes`,
  `getSelector` and `applyStyles`. No `ThemeProvider`. `useTheme` comes from `@mui/material-pigment-css`, client-only.
  Runtime theme switching works only by toggling CSS-variable selectors, such as a class on `<html>`.
- **Layout components:** use the adapters `Box`, `Container`, `Grid`, `Stack` and `Hidden` from
  `@mui/material-pigment-css`. Grid uses `gap` instead of margins.
- **RTL:** `css.defaultDirection` / `generateForBothDir`; `RtlProvider` + `useRtl` replace `theme.direction`.
- **React 19:** within the peer range; the probe ran React 19.3.1 without errors. CONFIRMED for the probe only.
- **SSR / prerender:** the output is a plain CSS file plus class names, so prerendering needs no style extraction
  step. INFERRED (not run). This is the property that would make "no rule inserted after `markMeasureStart()`" hold
  by construction.
- **Not covered:** CSS cascade layers (no `@layer` in the probe CSS), so ordering against CSS Modules relies on
  import order. INFERRED from probe CSS (`grep -c @layer` = 0).

---

## 4. MUI's own direction (what replaces Pigment)

| Source | What it says / does | Status |
|---|---|---|
| Blog "Material UI v9.0" (2026-04-08) | v9 = a11y, "`sx` prop performance improvements up to 30% for heavy `sx` usage", `color-mix()` theme vars. "What's next": **"Remove dependency on Emotion"**, more Base UI components | CONFIRMED |
| PR #48652 (draft, 2026-06-10) | `ThemeCSSProvider`: theme as CSS variables with no Emotion import; Slider/Toolbar base styles moved to CSS Modules with `:global(.Mui*)` selectors; `@mui/material/styles.css`; `@custom-media` breakpoints via Lightning CSS/PostCSS | CONFIRMED |
| PR #48745 (draft, 2026-06-30) | Same, but the theme is a **build-time generated static CSS file** (`generateThemeCss()`, `default-theme.css`); a parallel `@mui/material/css-modules/*` tree for tree-shaken CSS; `@mui/material-css-tools` Vite helper | CONFIRMED |
| PR #49001 (draft, 2026-08-20) | Multi-theme static CSS for Button/Slider; layers `mui.tokens, mui.base, mui.theme, mui.a11y`; "Added a **no-op styled-engine alias** … to prevent remaining runtime style injection" | CONFIRMED |
| PR #49157 (draft, 2026-09-17) | Split `@mui/material` into engine-free logic (state, events, a11y, DOM, `Mui*` classes, `ownerState`, inline CSS vars for values like a thumb at 37 %) and an Emotion styled shell. Rationale: "**Emotion is slow, and today there is no way to opt out of it.**" | CONFIRMED |
| v10.0.0-alpha.0 (2026-10-12) | No styling-engine change; Emotion still an (optional) peer | CONFIRMED release notes, `npm view` |

Reading (INFERRED): an Emotion-free Material UI is likely v10 or v11 work and would arrive as CSS Modules/static CSS,
not as compiled CSS-in-JS. Nothing usable lands within this project's timeline. The PoCs do confirm one useful
pattern: MUI components keep stable `Mui*` class names, so static CSS can target them.

---

## 5. The Emotion path on MUI 9.5: what it fixes and what stays

| Feature | Effect on our measurements | Status |
|---|---|---|
| `@mui/material@9.5.0` peers | `@emotion/react`/`styled` are listed **optional**, but `@mui/styled-engine` hard-depends on `@emotion/cache`, `sheet`, `serialize`. Without a replacement engine, Emotion is required in practice | CONFIRMED `npm view` |
| `cssVariables: true` | Palette/spacing/shadows become `var(--mui-*)` in one `:root` block. Switching colour scheme does not regenerate styles ("a lot less time is spent running JavaScript"). Trade-off: bigger HTML/CSS. It does **not** stop per-component serialisation or insertion | CONFIRMED MUI CSS theme variables docs; probe |
| `enableCssLayer` (`StyledEngineProvider`) | Wraps Emotion output in `@layer mui`; 9.1.1 fixed unlayered rules overriding layered ones (#48603) | CONFIRMED docs, release notes |
| `modularCssLayers` (theme, ≥7.2) | Sub-layers `mui.global`, `mui.components`, `mui.theme`, `mui.custom`, `mui.sx`; lets our CSS Modules sit above without specificity fights | CONFIRMED docs |
| `sx` 30 % faster (v9) | Cheaper per render, still runtime | CONFIRMED blog |
| Prerender extraction (`@emotion/server` / `createCache`) | Rules arrive in `<style data-emotion>`; on hydration the cache registers them, so already-rendered classes are not re-inserted. Serialise + hash still run for each styled render | INFERRED from Emotion SSR design; to verify with the guard |
| Dynamic `sx` values | New class + `insertRule` per distinct value (probe: `css-6lw27z`, no inline style) | CONFIRMED probe |

**Why "near zero during scroll" is plausible with Emotion (INFERRED):** Emotion only runs inside React render. PLAN
§6.5 rule 1 already forbids per-frame values via state/`sx`/Emotion, so a scroll scenario with no React commits does
no Emotion work. Remaining Emotion costs fall in (a) load and hydration, (b) interactions that mount new
components or states (dialog, menu, hover variants), and (c) any accidental re-render. The `STYLE-INJECTION` guard
catches (b) and (c) if they happen after `markMeasureStart()`.

---

## 6. Runtime JS that remains with any style engine (MUI 9.5.0 source)

| Mechanism | Where | Engine work it causes | Status |
|---|---|---|---|
| Component logic | 76 `@mui/material` + 32 `@mui/utils` modules for 8 components in the Pigment probe | React render/commit, `DefaultPropsProvider` context | CONFIRMED probe bundle |
| Transitions | `internal/Transition.js` (9.x replaced RTG's `Transition`, still imports `TransitionGroupContext`); `Fade`/`Grow`/`Slide` call `reflow(node)` = `node.scrollTop`; `Slide` reads `getBoundingClientRect`; `Collapse` reads `clientHeight` and sets `transitionDuration` inline. MUI 7.x still bundles RTG (6 modules in probe) | Forced layout at transition start; height/width transitions in Collapse | CONFIRMED source |
| Ripple | `ButtonBase/TouchRipple.js` (no RTG since 9.x; keyframes via styled); `LazyRipple` mounts on first interaction | DOM insert + keyframe animation on press | CONFIRMED source |
| FocusTrap (Dialog/Drawer/Modal) | `Unstable_TrapFocus/FocusTrap.js`: `focusin` + capture `keydown` listeners and **`setInterval(…, 50)`** while open | Timer outside `MotionClock`; conflicts with PLAN §6.5 rule 2 while a modal is open | CONFIRMED source l.270-285 |
| Scroll lock (Modal) | `ModalManager.js`: `getScrollbarSize`, `getComputedStyle(...).paddingRight`, sets `overflow: hidden` + padding on the scroll container | Forced style/layout + relayout on open/close | CONFIRMED source |
| Popover / Menu | `Popover.js`: anchor `getBoundingClientRect`; `window` `scroll` listener when `disableScrollLock`; debounced `resize` | Rect reads while open | CONFIRMED source |
| Popper (Tooltip, Autocomplete, etc.) | `@popperjs/core` `createPopper` (not Floating UI) | Scroll/resize listeners on scroll parents while open | CONFIRMED dependency, `BasePopper.js` |
| Tabs | Indicator `left`/`width` inline after `getBoundingClientRect` (probe under Pigment: `style="left: 90px; width: 90px;"`); `internal/animate.js` rAF for scroll buttons; `resize` listener | Layout-property animation (v1 lesson 5) | CONFIRMED source + probe |
| `useMediaQuery`, `useScrollTrigger` | `matchMedia` listeners; `useScrollTrigger` adds a `scroll` listener | Extra scroll callback if used | CONFIRMED source |
| Free-running rAF | `internal/animate.js`, `Slider/useSlider.js`, `TextareaAutosize.js` only | None at rest | CONFIRMED grep |

Consequence (INFERRED): "MUI everywhere" changes the parity and PL5 picture more through these behaviours than through
Emotion. Parts that animate on scroll should use MUI for structure and semantics (`Box`, `Typography`, `Button`,
`Container`) and keep the motion in our drivers. Tabs, Collapse, Slide and Grow should get their transitions replaced
(`TransitionComponent`/`slots.transition`, or `disable*`) before being measured.

---

## 7. Options for the plan

| Option | Engine at runtime | Works with | Main risk | Fit |
|---|---|---|---|---|
| **E. Emotion, made static at scroll time** | Emotion (load/hydrate/interaction) | MUI 9.5.x / 10 alpha, Vite 8, React 19, prerender | Insertions on interactions; per-render serialise cost; dynamic `sx` creates classes | **Default.** Supported, current, upgradeable |
| **P. Pigment 0.0.31 + MUI pinned 9.0.1** | none (static CSS + CSS vars) | Vite 8 (outside peer range), React 19, pnpm (probe) | Paused alpha; pins MUI to 2026-05-07 (misses 9.1–9.5 fixes: FocusTrap, transitions stuck, ripple leak); build ~25× slower; any new component may hit a wyw eval error; no `@layer` | **Measured variant only**, time-boxed |
| P'. Pigment + MUI 9.5 with patched TouchRipple | none | — | Patch-package on MUI internals; unknown further breakages | Not recommended (INFERRED) |
| S. MUI components + static CSS against `Mui*` classes + no-op styled-engine alias (what PR #49001 did in a sandbox) | none | any | Fights MUI's internal `styled` slots; undocumented; large manual CSS | Research curiosity only |
| B. Base UI (MUI's unstyled line) + CSS Modules | none | any | User asked for Material UI; PLAN rev 3 dropped Base UI | Out of scope unless the user reopens it |

Proposed plan changes (INFERRED, for the architect):
1. §6.5 rule 6: replace "MUI for 3 parts" with "MUI everywhere on Emotion, made static at scroll time":
   `createTheme({ cssVariables: true, modularCssLayers: '@layer mui, parts;' })`, `enableCssLayer`, Emotion
   extraction at prerender, no dynamic `sx`/`styled` props in parts (values via CSS vars on the element, as Pigment
   does), and visual overrides in CSS Modules against `Mui*` classes inside layer `parts`.
2. Keep the `STYLE-INJECTION` guard. Add a check that a scroll scenario has **zero React commits** after
   `markMeasureStart()` (React Profiler or a commit counter). This closes the Emotion confound at its source.
3. Add a global experiment flag `style-engine: emotion | pigment` on a frozen sub-tree (MUI pinned to 9.0.1 in that
   workspace only). It runs once in M2 to quantify Emotion's load/interaction cost (insert counts, style-recalc
   counts), then is dropped if Pigment breaks. Time box ~1 agent-day (budget is looser now; speed matters more).
4. Replace MUI transitions in measured parts. Treat FocusTrap's 50 ms interval as an allowed exception to the
   MotionClock rule while a modal is open, measured in its own interaction scenario.
5. R9 wording: the risk is now "MUI behaviours (transitions, Tabs, FocusTrap, scroll lock) and Emotion interaction-time
   inserts", mitigated by flags 2–4.

---

## 8. Open questions and risks

- Does Emotion hydration in Vite prerender really perform zero `insertRule` for SSR-present classes? Verify in M1
  with the guard. INFERRED.
- Which 9.1+ fixes matter if a Pigment variant pins 9.0.1? FocusTrap tab order (9.1.0 #48546), stuck exit transitions
  (9.3.1 #48881), LazyRipple leak (9.5.0 #49000). CONFIRMED that they postdate 9.0.1.
- Pigment `vite dev`/HMR and prerender were not probed.
- WebKit: no style-engine-specific concern found. Static CSS should be neutral. INFERRED.
- If MUI merges the CSS Modules PoCs during the project, `@mui/material/styles.css` + `ThemeCSSProvider` would give an
  official zero-runtime path. Re-check v10 betas monthly. INFERRED.

---

## Sources

- Pigment repo, releases, commits, issues: https://github.com/mui/pigment-css (queried via `gh`, 2026-10-17);
  release v0.0.31 https://github.com/mui/pigment-css/releases/tag/v0.0.31
- Pigment status discussion #424 (2026-06-08): https://github.com/mui/pigment-css/discussions/424
- Pigment pause comment (2025-05-22): https://github.com/mui/pigment-css/issues/388#issuecomment-2902532570
- Pigment README (master): https://github.com/mui/pigment-css/blob/master/README.md
- "What is the way forward for styling @ mui?" maintainer reply: https://github.com/mui/material-ui/issues/45759#issuecomment-2766269432
- Zero-runtime RFC: https://github.com/mui/material-ui/issues/38137
- MUI blog "2026 and beyond" (2026-01-01): https://mui.com/blog/2026-and-beyond/
- MUI blog "Material UI v9.0" (2026-04-08): https://mui.com/blog/introducing-material-ui-v9/
- Migrating to Pigment CSS: https://mui.com/material-ui/migration/migrating-to-pigment-css/
- CSS theme variables overview: https://mui.com/material-ui/customization/css-theme-variables/overview/
- CSS layers: https://mui.com/material-ui/customization/css-layers/
- Styling PoC PRs: https://github.com/mui/material-ui/pull/48652 , https://github.com/mui/material-ui/pull/48745 ,
  https://github.com/mui/material-ui/pull/49001 , https://github.com/mui/material-ui/pull/49157
- Releases v9.0.0–v10.0.0-alpha.0: https://github.com/mui/material-ui/releases (e.g. tag v10.0.0-alpha.0, v9.1.0, v9.1.1)
- Select + Pigment compile failure: https://github.com/mui/material-ui/issues/46592
- npm registry (queried 2026-10-17): `@pigment-css/{react,vite-plugin,nextjs-plugin,unplugin,theme}@0.0.31`,
  `@mui/material@9.5.0` / `10.0.0-alpha.0`, `@mui/material-pigment-css@9.5.0`, `@mui/system@9.5.0`,
  `@mui/styled-engine@9.5.0`, `@wyw-in-js/transform` (latest 2.6.0), `vite` (latest 8.3.4), `react` (19.3.1)
- MUI 9.5.0 package source (npm pack): `Unstable_TrapFocus/FocusTrap.js` l.270-285, `Modal/ModalManager.js`
  l.109-146, `Popover/Popover.js` l.150, 252, 276-280, `transitions/utils.js` l.14, `Fade/Fade.js` l.71,
  `Slide/Slide.js` l.44-62, `Collapse/Collapse.js` l.171-211, `Tabs/Tabs.js` l.338-364, `internal/Transition.js` l.15,
  `ButtonBase/TouchRipple.js` (9.1.0 introduced `getAnimationStyles(theme)`, absent in 9.0.1)
