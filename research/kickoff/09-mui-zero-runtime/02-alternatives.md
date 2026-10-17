# 09.02 · MUI everywhere without runtime CSS-in-JS: the alternatives

Kickoff research note for v2, written 2026-10-17. It feeds the Q4 rework that follows the user's decision on
2026-10-17 to use MUI everywhere. It is input for the plan, not the plan itself.

**Status words.** **CONFIRMED** means a cited source agrees: docs, package source at a pinned version, or npm
registry data queried today. **INFERRED** means my reading or proposal, not yet checked.

**Fixed constraints from the plan (rev 3).** The site uses React 19 + Vite (vite 8.3.4 per [06]), pnpm workspaces,
and is prerendered. Only production builds are measured. §6.5 rule 1 says no per-frame value goes through React
state, context, `sx` or Emotion. A `STYLE-INJECTION` guard fails a run if a style rule is inserted after
`markMeasureStart()`.

---

## 0. Answer in brief

1. **Your memory is right in principle: Pigment CSS compiles MUI's styles to static CSS at build time. Today it is
   not usable here.** It is on hold (alpha 0.0.31). Its Vite plugin declares support only for `vite ^4 || ^5 || ^6`,
   and we use Vite 8. It depends on `@mui/system ^6.1.6` and `@wyw-in-js/transform ^1.1.0`, which are two and one
   majors behind. MUI's own guide lists pnpm as a known problem. CONFIRMED (§1).
2. **The best route to "MUI everywhere" is Material UI 9.5 + Emotion with the styles compiled ahead of time.** I call
   this option (b+) "Emotion AOT":
   - At prerender, render every MUI component in every state the site uses.
   - Write the extracted rules to a static CSS file inside `@layer mui`.
   - Pre-mark those style ids as already inserted in the client Emotion cache, so Emotion never touches the DOM or
     CSSOM after hydration.

   The browser engines then see plain static CSS. Emotion's remaining cost is JS hashing during React renders, and
   §6.5 already keeps renders out of scroll frames. The mechanism is CONFIRMED in Emotion's source (§2). That the
   complete approach works is INFERRED, and spike S-AOT checks it (§8).
3. **Our own styling stays CSS Modules,** applied to MUI components through `className` and
   `slotProps.*.className`, in a layer above `mui`. The project bans `sx` and `styled()` (lint). StyleX,
   vanilla-extract, Panda, Linaria and Tailwind are all zero-runtime for **our** CSS. None of them removes Emotion
   from **MUI's own** components, so none of them is a substitute for (b+) (§3-§6).
4. **Fallback: Base UI + CSS Modules** for any part where (b+) fails its gate. This is the MUI-family headless
   library, zero-runtime, and its behaviour (focus trap, menu, tabs) comes from MUI. MUI stays in the remaining
   parts (§7).
5. **The styling engine does not fix MUI's widget behaviour.** Tabs animate the indicator's `left`/`width` after a
   rect read, and MUI transitions run through react-transition-group inline styles. This is true under Emotion,
   Pigment or anything else. These still need per-component overrides, whatever we pick (§9).

---

## 1. (a) Pigment CSS

| Fact | Value | Status |
|---|---|---|
| What it is | Zero-runtime CSS-in-JS: "extracts the colocated styles to their own CSS files at build time" | CONFIRMED, `gh repo view mui/pigment-css` |
| Status | Repo description: "Alpha phase, currently, on hold". MUI blog: "remains in alpha phase and is currently on hold … progressing further would require a different approach" | CONFIRMED, https://mui.com/blog/2026-and-beyond/ |
| Latest | `@pigment-css/react` 0.0.31 (2026-05-22). Before that, 0.0.30 (2025-01-14): one release in 16 months. Last commit 2026-06-06 ("Normalization between repositories"). 0.0.31 bumped wyw and added Next 16 | CONFIRMED, npm `time`; `gh api repos/mui/pigment-css/commits` |
| Built on | `@wyw-in-js/transform ^1.1.0` and `@wyw-in-js/processor-utils`. wyw-in-js latest is **2.6.0** (2026-10-15) | CONFIRMED, `npm view @pigment-css/react@0.0.31 dependencies` |
| MUI bridge | `@mui/material@9.5.0` lists `@mui/material-pigment-css ^9.5.0` as an optional peer. That adapter (9.5.0, 2026-10-12) peers `@pigment-css/react ^0.0.30 \|\| ^0.0.31` | CONFIRMED, npm |
| Version skew | `@pigment-css/react` depends on `@mui/system ^6.1.6`, while Material UI 9.5 uses `@mui/system 9.5.0`. Two copies of `@mui/system` would be installed | CONFIRMED (deps); effect INFERRED |
| Vite | `@pigment-css/vite-plugin@0.0.31` peers `vite ^4.0.0 \|\| ^5.0.0 \|\| ^6.0.0`. We are on vite 8.3.4. Open Vite issues: #67, #409 (CJS Node API deprecated), #352 (wrapping MUI components with `styled` breaks after 0.0.20), #68 (`extendTheme()` crashes) | CONFIRMED, npm; `gh search issues --repo mui/pigment-css vite` |
| Bundlers | MUI guide: Next.js App Router with webpack 5 (no Turbopack), and Vite. pnpm has a known issue ("use npm or yarn until it's resolved") | CONFIRMED, https://mui.com/material-ui/migration/migrating-to-pigment-css/ |
| Usage | 31,939 downloads/week (Emotion react: 20.6 M) | CONFIRMED, api.npmjs.org, 2026-10-17 |

**How it works with MUI components.** The bundler plugin swaps MUI's `styled`/`sx` for Pigment's versions and
evaluates them at build time. `Box`, `Stack`, `Grid`, `Container` and `useTheme` come from
`@mui/material-pigment-css`. CONFIRMED (migration guide).

**Limits on dynamic styles.** Anything that depends on runtime state throws at build time. `sx` values that depend
on variables must become CSS variables set inline. `styleOverrides` callbacks that read `ownerState` must become
`variants`. `defaultProps` move into `DefaultPropsProvider`. Grid spacing switches from margin to `gap`, which
changes layout and therefore parity. CONFIRMED (migration guide).

These limits are fine for us, because per-frame values never go through styles (§6.5).

**Assessment.**
- Build-time: yes. Zero runtime insertion: yes, in principle.
- Maturity: poor, and the project is paused by its owner.
- Migration cost: high. Expect forked plugin work to run on Vite 8 with pnpm.
- Closeness to "MUI everywhere": highest. It is the same components and the same theming API.

**Verdict: not primary.** It is worth an optional half-day smoke test, Pigment on Vite 8 with three MUI components
(INFERRED value), because a pass would give the purest result. Nothing in the plan should depend on it.

## 2. (b) MUI + Emotion with critical CSS extraction at prerender

**Are styles inserted again at hydration? No, for every style id that was in the server HTML.** The MUI SSR guide
says the CSS "will be injected a second time before removing the server-side injected CSS". That sentence is
outdated. Emotion 11's source shows otherwise:

- `@emotion/cache@11.14.0` `src/index.ts` l.63-86: on creation, Emotion moves every SSR
  `<style data-emotion="css …">` into `<head>` and marks it `data-s`.
- l.100-113: it reads each tag's `data-emotion` attribute and sets `inserted[id] = true` for every id listed. Then
  `sheet.hydrate(nodes)` (l.252) adopts those tags.
- `@emotion/utils` `insertStyles` inserts only when `cache.inserted[serialized.name] === undefined` (l.54). So
  components rendered at prerender hydrate **without new rules**.
- `@emotion/react@11.14.0` `src/global.tsx` l.101-123: `<Global>` (used for CssBaseline and the CSS-variables sheet)
  finds its SSR tag, hydrates it, and skips the insert while rehydrating.

All CONFIRMED (source at the pinned versions, via jsDelivr).

**What still happens at runtime.** These are CONFIRMED from the same source unless marked.

1. **Startup DOM moves.** The SSR `<style>` tags are moved into `<head>`, and `StyledEngineProvider` prepends a
   `<meta name="emotion-insertion-point">` (`@mui/styled-engine@9.5.0` `StyledEngineProvider.js` l.56-67). This all
   happens before `markMeasureStart()`, so it is a hydration cost and outside the scroll scenarios.
2. **Serialization on every render.** Each render of a styled MUI component runs `serializeStyles` and hashes the
   result (`emotion-element.tsx` l.142). This is main-thread JS only, with no style, layout or paint work.
   Under §6.5, nothing re-renders per frame.
3. **New insertions for styles not in the prerendered HTML.** This includes:
   - an opened Dialog, Menu or Drawer whose paper and backdrop were never rendered;
   - `ownerState` variants that first appear on interaction, such as a selected Tab or a disabled button;
   - any new `sx` object.

   Each insertion is a CSSOM mutation that both engines must invalidate against. This is the real confound, and the
   reason the `STYLE-INJECTION` guard exists. (Invalidation cost INFERRED from the sheet design; to be measured.)
4. **The theme as CSS variables.** `ThemeProvider` with `cssVariables: true` emits the variables through Emotion
   `GlobalStyles` (`@mui/system@9.5.0` `cssVars/createCssVarsProvider.js` l.260). They are covered by extraction.
   Mode switches do not regenerate stylesheets. CONFIRMED,
   https://mui.com/material-ui/customization/css-theme-variables/overview/

**(b+) "Emotion AOT": close the gap in item 3.** All INFERRED and to be spiked; the mechanism is confirmed above.

- **Style census route.** A build-only route renders every MUI component the site uses in every state it can reach:
  open overlays, the selected and unselected Tab, disabled and hover-variant props. Pseudo-classes such as `:hover`
  live inside the same rule, so they need no census.
- **Build step.** `renderToString` the site and census routes, then run `extractCriticalToChunks` (`@emotion/server`
  11.11.0). Write the rules to `mui.[hash].css` wrapped in `@layer mui`, and write the ids to `emotion-ids.json`.
- **Client.** Create the cache with the same key. Before `hydrateRoot`, set `cache.inserted[id] = true` for every id
  in the json. Emotion then finds nothing to insert for anything in the census.
- **Measurement builds.** Wrap `cache.insert` to count misses and report them to the harness. A miss means the
  census is incomplete; it is a build failure, not a silent runtime cost.
- **Determinism.** Class names are hashes of the serialized styles, so server and client agree when the theme and
  code are identical. The tags carry no per-request state.

**Assessment.**
- Build-time CSS: yes, with (b+). Runtime: JS serialization on render only.
- Dynamic styles: unrestricted, but any style missing from the census becomes a counted insertion.
- Maturity: high. Emotion 11 is stable, with 20.6 M downloads/week, and MUI 9.5 is its default engine.
- Migration cost: low. It is standard MUI plus one build script and a census list.
- Closeness to "MUI everywhere": full. It is the official engine with no API limits.

**Verdict: primary.**

## 3. (c) wyw-in-js / Linaria

- **wyw-in-js** ("why wait") is the build-time evaluator shared by Linaria and Pigment.
  `@wyw-in-js/transform` is at 2.6.0 (2026-10-15), with active monthly releases since 2.0.0 (2026-06-14).
  `@linaria/react` 8.2.0 (2026-08-10) pins `@wyw-in-js/* 2.4.0`. CONFIRMED (npm).
- **Linaria dynamic styles.** Prop functions "will use CSS variables under the hood and can change dynamically in
  runtime". The value arrives through the `style` prop. CONFIRMED,
  https://github.com/callstack/linaria/blob/master/docs/BASICS.md
- **Interaction with MUI.** MUI's styled-engine has three implementations: Emotion (default),
  `@mui/styled-engine-sc` 9.5.0 (styled-components, also runtime), and the Pigment adapter. **There is no Linaria
  adapter.** Linaria can style our own wrappers and pass `className` into MUI components, but MUI's internals stay on
  Emotion. CONFIRMED (npm packages); "no adapter" CONFIRMED by absence in `@mui/material` peers.
- **Writing our own wyw processor for `@mui/system`'s `styled`/`sx`** means rebuilding Pigment, which MUI itself
  paused because "the underlying problems were not fully solved". INFERRED: too costly.

**Verdict.** It is useful only as a zero-runtime authoring style for our own parts. On that it ties with CSS Modules
and adds a Babel pass. Not recommended.

## 4. (d) StyleX, vanilla-extract, Panda CSS for our own parts, with MUI themed through CSS variables

The common point: all three are build-time for **our** CSS. MUI components still get their own CSS from Emotion.
Theming through CSS variables (`cssVariables: true`, `--mui-*`) means **our** CSS can read MUI's tokens. It does
**not** make MUI's component styles static. So (d) only works on top of (b)/(b+); it does not replace them.
CONFIRMED (MUI's engine is chosen by `@mui/styled-engine`; the variables are emitted through Emotion
`GlobalStyles`, §2).

| | StyleX 0.19.1 | vanilla-extract 1.21.3 | Panda CSS 2.2.0 |
|---|---|---|---|
| Model | Babel/unplugin compiler to atomic CSS | `.css.ts` files evaluated at build time | Static analysis of `css()`/recipes, then generated CSS |
| Dynamic values | Style functions compile to static rules that read a CSS variable "set at runtime" (CONFIRMED, https://stylexjs.com/docs/learn/styling-ui/defining-styles/) | `@vanilla-extract/dynamic` `assignInlineVars` sets inline variables (INFERRED from docs, not fetched today) | Not extractable from runtime state. "Panda does not run a JavaScript interpreter"; the docs recommend CSS variables in `style` or `staticCss` (CONFIRMED, https://panda-css.com/docs/guides/dynamic-styling) |
| Runtime JS | `stylex.props` merges class names | Near zero (class strings) | The generated `styled-system` helpers (`css`, `cva`, `token`) run in the client |
| Downloads/week | 2.13 M | 2.70 M | 0.53 M |
| Parity fit | Poor. Atomic classes do not mirror the snapshot's selectors, so the PL2 computed-style diff is still fine, but the source is harder to diff against the original | Good. One rule per class, close to the original CSS | Medium |
| Extra build step | Babel plugin (and with it, a second compiler next to Vite's) | Vite plugin 5.2.6 | PostCSS + codegen |

**Verdict.** None is better than CSS Modules for restating a snapshot's CSS, and the plan already uses CSS Modules
with zero runtime. vanilla-extract is the only one worth adding, and only if typed tokens shared with MUI's theme
become valuable. INFERRED.

## 5. (e) Base UI / headless MUI + our own compiled CSS (fallback only)

- `@base-ui/react` 1.9.0 (2026-10-09), 17.4 M downloads/week. The MUI blog calls it "our long-term direction for
  foundational, unstyled components" and says "Base UI is where we are concentrating our foundational work going
  forward". CONFIRMED (npm; https://mui.com/blog/2026-and-beyond/).
- It is fully zero-runtime for styles, styled with CSS Modules. It covers the behaviour we would take from MUI:
  Dialog focus trap, Menu, Tabs semantics. It is not Material Design, and it does not use the Material UI component
  API or theme. That is fine for parity, since the original is not Material either. CONFIRMED [02 §5].
- Migration cost from (b+): per part, swap the MUI component for its Base UI equivalent and move the overrides from
  `slotProps.*.className` to Base UI's parts. INFERRED: about 0.5 agent-day per part.
- Closeness to "MUI everywhere": partial. It is MUI's library, but not Material UI.

**Verdict: the fallback,** used per part only where (b+) fails its gate (§8).

## 6. (f) Tailwind with MUI (`enableCssLayer`)

- Tailwind 4.3.3 is build-time. MUI documents the layer order `@layer theme, base, mui, components, utilities;`,
  with `enableCssLayer` on `StyledEngineProvider` for Vite. Classes go on `className` and
  `slotProps.{slot}.className`. A `@theme inline` block maps MUI tokens to utilities. CONFIRMED,
  https://mui.com/material-ui/integrations/tailwindcss/tailwindcss-v4/
- The page states "Material UI relies on Emotion for styling", so Emotion still runs for MUI's components.
  CONFIRMED.
- What we take from it: the **layer contract**, which (b+) uses with `parts` (CSS Modules) in place of Tailwind's
  `utilities`. Tailwind itself adds nothing for parity work. Utility classes restate the original's rules less
  directly than a CSS Module.

**Verdict.** Do not adopt Tailwind. Do adopt the layer order.

## 7. Comparison

| Option | Build-time or runtime (MUI internals) | Our parts | Dynamic style limits | Maturity (2026-10-17) | Migration cost | Closeness to "MUI everywhere" |
|---|---|---|---|---|---|---|
| (a) Pigment | build | build | No runtime-dependent styles; `ownerState` callbacks become variants; Grid uses `gap` | alpha, on hold; Vite ≤6; pnpm issue; `@mui/system` 6 vs 9 | high, likely a fork | full (same API) |
| **(b+) Emotion AOT** | **build output + runtime hash only**; insertions = census misses (guarded) | CSS Modules | none (a census miss is a counted insertion) | high | **low** | **full** |
| (b) Emotion SSR, plain | runtime for anything not in the initial HTML | CSS Modules | none | high | lowest | full |
| (c) Linaria / wyw | runtime (Emotion) | build | prop values become CSS variables | active (wyw 2.6.0) | medium | partial: MUI internals unchanged |
| (d) StyleX / VE / Panda | runtime (Emotion) | build | variables or `staticCss` | stable | medium | partial: MUI internals unchanged |
| (e) Base UI + CSS Modules | none | build | none | stable 1.9.0 | medium per part | low to medium (MUI family, not Material UI) |
| (f) Tailwind + layers | runtime (Emotion) | build | arbitrary values must be static | very high | medium | partial: MUI internals unchanged |

Per-frame values never go through any of these, by §6.5 rule 1. "Dynamic style limits" only matter for state
changes on interaction (open, select, disable).

## 8. Recommendation and how to check it

**Primary: (b+) Emotion AOT + CSS Modules overrides + layers.** All rules INFERRED, ready for the plan:

1. Material UI 9.5.0 with `cssVariables: true` and `enableCssLayer`. Layer order: `@layer reset, mui, parts, flags;`.
2. Our CSS goes in CSS Modules in `@layer parts`, applied through `className` and `slotProps.*.className`.
   Lint bans `sx`, `styled`, `css` from `@mui/*`/`@emotion/*` under `src/parts/**` (`no-restricted-imports` plus an
   ast-grep rule for the `sx` prop). This leaves Emotion with only MUI's own internal styles, which the census
   covers.
3. Build: a census route plus `extractCriticalToChunks` produces `mui.[hash].css` and `emotion-ids.json`. The client
   pre-marks `cache.inserted`.
4. Measurement builds wrap `cache.insert`. One miss fails the build's census test, and the existing
   `STYLE-INJECTION` guard covers the run.
5. Keep the `impl: plain | mui` variant pair. It now measures what MUI costs **after** AOT: hydration JS and DOM
   depth. Emotion insertion is no longer part of that cost.

**Spike S-AOT (1 agent-day; add to Appendix B).** Pass criteria, all to be measured:

- Covers Button, Dialog (open and closed), Menu, Tabs and Drawer in the harness.
- Zero `insertRule` or `<style>` mutations after hydration in both Chromium and WebKit, checked with a CDP
  `CSS.styleSheetAdded` listener plus a `CSSStyleSheet.prototype.insertRule` probe.
- PL5 work counts for a closed-overlay scroll scenario are equal between `impl: plain` and `impl: mui`.
- Opening each overlay causes no style insertions.

**Fallback: (e) Base UI + CSS Modules, per part.** Use it for any part whose census cannot be completed, or whose
PL5/PL6 deltas under `impl: mui` exceed the frozen bands. The rest of the site stays on (b+), so "MUI everywhere"
degrades part by part, not all at once.

**Optional, in parallel:** a half-day Pigment smoke test (Vite 8, pnpm, three components). If it passes, reconsider
it at M2. Nothing waits on it.

## 9. What no styling engine fixes (applies to every option)

- **Tabs** transition the indicator's `left`/`width` after `getBoundingClientRect`, in `@mui/material@9.5.0`
  `Tabs/Tabs.js` l.180-200 and l.380-420. CONFIRMED [02 §5.2]. Override it: hide the built-in indicator through
  `slotProps.indicator` and drive our own `transform` indicator, or restate the original's. INFERRED.
- **Transitions** (`Fade`, `Grow`, `Slide`, `Collapse`) are react-transition-group and write inline styles from JS.
  Replace them through `slots.transition` / `TransitionComponent` with the original's keyframes. INFERRED; checked at
  PL4.
- **Scroll-coupled MUI hooks** such as `useScrollTrigger` re-render on scroll, which breaks §6.5. Ban them (lint).
  INFERRED.
- **DOM depth.** MUI wraps elements (Paper, Backdrop, Portal, ButtonBase ripple). This can move PL0/PL1 and the
  element counts in PL5. Turn ripples off with `disableRipple` theme-wide, and map anchors in `parity.json`.
  INFERRED.

## Sources

- MUI, "2026 and beyond": https://mui.com/blog/2026-and-beyond/ (fetched 2026-10-17)
- MUI, migrating to Pigment CSS: https://mui.com/material-ui/migration/migrating-to-pigment-css/
- MUI, server rendering: https://mui.com/material-ui/guides/server-rendering/
- MUI, Tailwind v4 integration: https://mui.com/material-ui/integrations/tailwindcss/tailwindcss-v4/
- MUI, CSS theme variables: https://mui.com/material-ui/customization/css-theme-variables/overview/
- Pigment repo: `gh repo view mui/pigment-css`; commits API; issues #67, #68, #352, #382, #409
- Emotion source (jsDelivr): `@emotion/cache@11.14.0/src/index.ts`, `@emotion/react@11.14.0/src/global.tsx`,
  `@emotion/react@11.14.0/src/emotion-element.tsx`, `@emotion/utils@1.4.2/src/index.ts`,
  `@emotion/sheet@1.4.0/src/index.ts`
- MUI source (jsDelivr): `@mui/system@9.5.0/cssVars/createCssVarsProvider.js`,
  `@mui/styled-engine@9.5.0/StyledEngineProvider/StyledEngineProvider.js`
- StyleX: https://stylexjs.com/docs/learn/styling-ui/defining-styles/
- Panda: https://panda-css.com/docs/guides/dynamic-styling
- Linaria: https://github.com/callstack/linaria/blob/master/docs/BASICS.md
- npm registry (`npm view`, 2026-10-17): @mui/material 9.5.0 (next 10.0.0-alpha.0, still peers Emotion),
  @mui/material-pigment-css 9.5.0, @pigment-css/react 0.0.31, @pigment-css/vite-plugin 0.0.31,
  @wyw-in-js/transform 2.6.0, @linaria/react 8.2.0, @stylexjs/stylex 0.19.1, @vanilla-extract/css 1.21.3,
  @vanilla-extract/vite-plugin 5.2.6, @pandacss/dev 2.2.0, tailwindcss 4.3.3, @base-ui/react 1.9.0,
  @emotion/react 11.14.0, @emotion/server 11.11.0, @mui/styled-engine-sc 9.5.0, vite 8.3.4. Weekly downloads from
  api.npmjs.org.
- Kickoff note [02] §5 (MUI 9.5.0 facts, Tabs source lines).
