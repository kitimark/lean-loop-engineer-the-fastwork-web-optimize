# 09-04 Hands-on spike: MUI with zero-runtime styling (Pigment CSS) vs Emotion

Date: 2026-10-17. Machine: macOS (Darwin 27), Node v24.14.0, npm 11.9.0.
Scratch location (not in repo): `<session scratchpad>/mui-spike/`
Labels: **CONFIRMED** = I observed it in this spike. **INFERRED** = my reading of the evidence, not tested directly.

## TL;DR

1. **Zero-runtime MUI works.** MUI v7.3.11 with `@pigment-css/vite-plugin@0.0.30` and Vite 6.4.4 builds with no patches. In the bundle, **0 Emotion runtime code**, **0 `<style>` tags** and **0 CSSOM insertions** at load, during scroll, on tab switches, on the Dialog and on hover. All styles land in one static `.css` file (~264 rules), loaded with a `<link>` (CONFIRMED in Chrome 155 and WebKit 27.2).
2. **Latest MUI (9.5.0) does NOT build with Pigment unpatched.** The build stops with `TouchRipple.mjs: This identifier cannot be used in the template, because it is a function parameter.` This regression came with MUI 9.1.0, from PR #48357 "[transitions] Support `prefers-reduced-motion`" (2026-06-04). MUI **9.0.1** still builds with Pigment 0.0.30. A one-file patch of `TouchRipple.mjs` makes 9.5.0 build and run, but the ripple loses its reduced-motion handling (CONFIRMED).
3. **Pigment fails silently on dynamic `sx`.** The docs say it throws. In practice `sx={{ width: \`${p}%\` }}` built without error and produced `width:null%` in the CSS, and the hook that computed `p` was tree-shaken away (CONFIRMED). We need our own build gate (see Recommendations).
4. **Size:** the Pigment build is ~19% smaller in JS than Emotion (gzip 99.5 kB vs 126.2 kB on v7; brotli 85.8 vs 109.3 kB), plus a 6.5 kB gzip CSS file. Over half of the JS size gap is `@mui/system` runtime (34 kB raw → 1.3 kB). The other big piece is Emotion/stylis plus MUI's own runtime style code (@mui/material shrinks by ~19 kB raw) (CONFIRMED).
5. **Key measurement insight:** in Chrome traces, the deterministic work counts during scroll were **identical** for naive Emotion and Pigment. Naive Emotion means a dynamic `sx` value inserting 100 rules during the scroll. The identical counts were UpdateLayoutTree 179, elementCount 218, Layout 168, dirtyObjects 336, Paint 323. Only wall time differed: UpdateLayoutTree ≈ 20–24 ms vs 8–10 ms. **Our deterministic counters as planned would not see CSS-in-JS pollution.** Add a "CSSOM mutation count" counter (the insertRule/MutationObserver probe below) as a hard metric (CONFIRMED for Chromium counts; the WebKit insert counts match).

## Versions (npm view, 2026-10-17)

| package | latest dist-tag | notes |
|---|---|---|
| @mui/material | 9.5.0 (latest), 7.3.11 (latest-v7), 10.0.0-alpha.0 (next) | 9.5.0 peer: `@mui/material-pigment-css ^9.5.0` (optional), `@emotion/react ^11.5.0` |
| @mui/material-pigment-css | 9.5.0 / 7.3.11 / 9.0.1 | 9.5.0 peers `@pigment-css/react ^0.0.30 \|\| ^0.0.31`; 7.3.11 and 9.0.1 peer `^0.0.30` only |
| @pigment-css/react | 0.0.31 (2026-05-22); 0.0.30 (2025-01-14) | still 0.0.x alpha; deps include `@mui/system ^6.1.6`, `@emotion/*` (build-time use) |
| @pigment-css/vite-plugin | 0.0.31 | peer `vite ^4 \|\| ^5 \|\| ^6` (no Vite 7/8 in peer range) |
| vite | 8.3.4 (latest), 6.4.4 (previous) | |
| @vitejs/plugin-react | 6.1.2 | 4.7.0 used with Vite 6 |
| react / react-dom | 19.3.1 | |
| @emotion/react / styled | 11.14.0 / 11.14.1 | |
| playwright-core | 1.64.1 | Chromium via `channel:'chrome'` (Google Chrome 155.0.8059.80); WebKit 27.2 (playwright webkit r2370) |

Repo status: `mui/pigment-css` is not archived and was last pushed 2026-10-08. It has 148 open issues, and its last release is v0.0.31 (2026-05-22) (`gh api repos/mui/pigment-css`). The MUI doc "Migrating to Pigment CSS" on `master` still says "currently in the early alpha stage" and refers only to v6/v7 (`docs/data/material/migration/upgrade-to-v6/migrating-to-pigment-css.md`). The repo no longer has an `apps/` directory, where the Pigment Vite/Next test apps used to live, so INFERRED: MUI no longer tests v9 against Pigment in CI, which matches the v9.1 regression shipping unnoticed. `gh search issues` found no existing issue for the TouchRipple breakage.

## Builds attempted

All builds use the same app: `shared/App.jsx` and `shared/theme.js`. It has a themed `createTheme`: `cssVariables:true`, custom palette and shape, typography with `textTransform:'none'`, `MuiButton` styleOverrides plus `variants`, and a `MuiCard` override. On the page:
- a sticky `AppBar` with `useScrollTrigger` → `elevation`, plus `Toolbar`
- `Tabs` with 4 `Tab`s (state)
- a `Button` with `sx`
- a `Dialog` (open/close)
- 60 `Card`s (outlined, `sx` with `&:hover`)
- three `styled('section'|'div'|'span')` with theme callbacks
- a scroll-progress bar driven by React state on every scroll event

| app dir | MUI | styling | Pigment | Vite | result |
|---|---|---|---|---|---|
| `pigment-app` | 9.5.0 | Pigment | 0.0.31 (wyw-in-js 1.1.0) | 6.4.4 | **FAIL**: TouchRipple error (log `build-pigment-1.log`). **PASS after a 1-file patch** (`build-pigment-v9-patched.log`) |
| `pigment-v7` | 7.3.11 | Pigment | 0.0.30 (wyw-in-js 0.5.5) | 6.4.4 | **PASS** unpatched (`build-pigment-v7.log`) |
| `pigment-v901` | 9.0.1 | Pigment | 0.0.30 | 6.4.4 | **PASS** unpatched |
| `pigment-v7-vite8` | 7.3.11 | Pigment | 0.0.30 | **8.3.4** + plugin-react 6.1.2 | **PASS**, but needs `--legacy-peer-deps`. CSS gets reordered/minified differently (32.9 kB vs 34.6 kB) |
| `emotion-v7` | 7.3.11 | Emotion (default), "naive" dynamic `sx` for the progress bar | – | 6.4.4 | PASS |
| `emotion-v7cv` | 7.3.11 | Emotion, progress bar uses static `sx` + CSS var via `style` | – | 6.4.4 | PASS |
| `emotion-v9` | 9.5.0 | Emotion, naive dynamic `sx` | – | 6.4.4 | PASS |

### Commands (Pigment, the working v7 path)

```bash
npm i --save-exact react@19.3.1 react-dom@19.3.1 @mui/material@7.3.11 \
  @mui/material-pigment-css@7.3.11 @pigment-css/react@0.0.30
npm i -D --save-exact vite@6.4.4 @vitejs/plugin-react@4.7.0 @pigment-css/vite-plugin@0.0.30
npx vite build
```

```js
// vite.config.js
import { pigment } from '@pigment-css/vite-plugin';
import { theme } from './src/theme.js';           // createTheme({ cssVariables: true, ... })
export default defineConfig({ plugins: [pigment({ transformLibraries: ['@mui/material'], theme }), react()] });
// main.jsx: import '@mui/material-pigment-css/styles.css'  (placeholder that the plugin fills with the theme CSS)
// custom styled: import { styled } from '@mui/material-pigment-css'   (Emotion app: from '@mui/material/styles')
// Box: import Box from '@mui/material-pigment-css/Box'
```

### Errors and workarounds

1. **npm ERESOLVE**: `@mui/material-pigment-css@7.3.11` peers `@pigment-css/react@^0.0.30`, so 0.0.31 is rejected. Workaround: pin 0.0.30 for both `@pigment-css/react` and `@pigment-css/vite-plugin`. Only `material-pigment-css@9.5.0` accepts 0.0.31.
2. **MUI 9.5.0 + Pigment 0.0.31 build error** (also with Pigment 0.0.30):
   ```
   [vite-plugin-zero-runtime] node_modules/@mui/material/ButtonBase/TouchRipple.mjs:
   This identifier cannot be used in the template, because it is a function parameter.
   > 119 | function getAnimationStyles(theme) {   ...   const styles = css`...${theme.transitions.easing.easeInOut}...`
   ```
   - Cause: since 9.1.0, `TouchRipple` builds its keyframe CSS inside `getAnimationStyles(theme)` with a `css` template that reads `theme` and `theme.motion.reducedMotion`. Pigment/wyw-in-js cannot evaluate that statically (`git log` of `packages/mui-material/src/ButtonBase/TouchRipple.js`: #48357, 2026-06-04).
   - Present in 9.1.0 and 9.2.0 through 9.5.0; absent in 9.0.1 (checked the tarballs).
   - `theme.motion` is also referenced in Tabs, Fade, Grow, Slide, Zoom, Collapse, SwipeableDrawer, SpeedDialAction and transitions/utils. In this app only TouchRipple broke the build. Other components were not tested.
   - Workaround: a Node script removes `getAnimationStyles` and inlines static animation CSS (easing `cubic-bezier(0.4,0,0.2,1)`, 200 ms). The patched 9.5.0 app then builds and runs with 0 page errors. In a real repo this would be a `patch-package` patch. It drops reduced-motion support for the ripple.
3. **Warnings, not errors:** wyw-in-js 1.1.0 (Pigment 0.0.31) prints 12× `Unknown import reached during eval (Node resolver fallback) ... source: react`, which its hint says can be silenced with `importOverrides`. Pigment 0.0.30 instead prints Rollup warnings: `/*#__PURE__*/ ... contains an annotation that Rollup cannot interpret` for ~10 MUI files. Neither affects the output.
4. **Vite 8**: the plugin peer range stops at Vite 6. `npm i --legacy-peer-deps` with Vite 8.3.4 built and ran correctly in this spike. Not tested: dev server/HMR (INFERRED: unsupported territory, so expect breakage).
5. **Silent miscompile of dynamic sx (Pigment)**: putting a React state value inside `sx` (`width: \`${p}%\``) built with **exit 0**. Output CSS: `.sam9zt5{...;width:null%}`, and the component's `useScrollPct()` call was removed from the JS (`function Mx(){return j.jsx(Ox,{"data-testid":"progress",...Fa("sam9zt5",{})})}`). The MUI docs claim Pigment "will throw an error" for state-dependent styles. In this case it did not. Correct pattern: `sx={{ width: 'var(--p)' }} style={{ '--p': p + '%' }}`. That compiles to `width:var(--p)` and keeps the hook.

## Bundle inspection (final builds, `vite build`, no sourcemaps)

Bytes; gzip -9; brotli default.

| app | JS raw / gz / br | CSS raw / gz / br | `data-emotion` | `insertRule` | `stylis` |
|---|---|---|---|---|---|
| pigment-v7 (MUI 7.3.11) | 326,124 / 99,541 / 85,824 | 34,642 / 6,535 / 5,562 | 0 | 0 | 0 |
| pigment-v901 (MUI 9.0.1) | 331,083 / 101,434 / 87,297 | 34,525 / 6,516 / 5,538 | 0 | 0 | 0 |
| pigment-app (MUI 9.5.0 patched) | 331,914 / 101,896 / 87,906 | 34,952 / 6,580 / 5,630 | 0 | 0 | 0 |
| pigment-v7-vite8 | 334,960 / 99,171 / 85,138 | 32,926 / 6,349 / 5,457 | 0 | 0 | 0 |
| emotion-v7 | 401,995 / 126,168 / 109,276 | – (all CSS injected at runtime) | 7 | 1 | 1 |
| emotion-v9 | 412,569 / 130,376 / 112,923 | – | 7 | 1 | 1 |

- The one `createElement("style")` hit in the Pigment bundles is React 19 DOM's `<style precedence>` resource code, not Emotion (checked context).
- The Pigment bundle still contains `@emotion/is-prop-valid` (4.3 kB) and `@emotion/memoize` (0.1 kB). These are used by Pigment's runtime `styled` to filter props. There is no serializer, cache or style injection. `@emotion/*` packages are still *installed* as deps of `@pigment-css/react`.
- `sx` is compiled to class names. `<Typography sx={{flexGrow:1,...}}>` becomes `...In("s1ow37j7",{})`, a tiny helper that merges className/style. `styled('div')(({theme})=>...)` becomes `zt("div")({classes:["gphk1bk"]})`. The theme becomes `:root{--mui-...}` CSS variables in the CSS file.

source-map-explorer 2.5.3 per-package breakdown (raw bytes in the minified JS):

| package | pigment-v7 | emotion-v7 |
|---|---|---|
| react-dom | 209,808 | 210,067 |
| @mui/material | 76,287 | 94,977 |
| @mui/system | 1,342 | 34,189 |
| @emotion/* + stylis + hoist-non-react-statics | 4,355 | ~21,500 |
| @pigment-css/react | 2,903 | – |
| total | 324,450 | 400,475 |

Takeaway: react-dom is ~65% of either bundle. Pigment removes ~76 kB raw / ~27 kB gzip of styling runtime.

## Headless browser measurement

Script: `scratchpad/mui-spike/measure/measure.mjs`, using playwright-core 1.64.1 with a local static server.
- Viewport 390×844 @1x.
- An init script patches `CSSStyleSheet.prototype.{insertRule,deleteRule,replace,replaceSync,addRule}` and runs a `MutationObserver` on `document`, which records `<style>` and `<link>` additions and style text changes. Events are tagged by phase.
- Phases:
  - load: `load` event + 500 ms
  - scroll: rAF loop, 120 px/frame to the bottom and back, 168 frames, maxY 10031; the AppBar `scrolled` state toggled
  - tabs: click 4 tabs
  - dialog: open and close
  - hover: 5 cards
- Chromium only: CDP `Performance.getMetrics`, cumulative values.
- Second script: `trace.mjs` records a CDP trace of the scroll phase only and sums `UpdateLayoutTree` (+`elementCount`), `Layout` (+`dirtyObjects`), `Paint`, `PrePaint` and `Layerize`.

Commands:
```bash
node measure.mjs chromium 3 pigment-v7=../pigment-v7/dist pigment-v9p=../pigment-app/dist \
  emotion-v7=../emotion-v7/dist emotion-v7cv=../emotion-v7cv/dist emotion-v9=../emotion-v9/dist > chromium.json
node measure.mjs webkit 2 ...same args... > webkit.json      # after: npx playwright-core install webkit
node trace.mjs 2 ...same args...
```

### CSSOM / style-tag counts. Identical in Chrome 155 (3 runs) and WebKit 27.2 (2 runs); zero variance.

Per-phase increments:

| app | `<style>` tags | styleSheets | CSS rules after load | insertRule: load | scroll | tabs | dialog | hover |
|---|---|---|---|---|---|---|---|---|
| pigment-v7 | 0 | 1 (`<link>`) | 264 | 0 | 0 | 0 | 0 | 0 |
| pigment-v9p (9.5.0 patched) | 0 | 1 | 266 | 0 | 0 | 0 | 0 | 0 |
| emotion-v7 (naive dynamic sx) | 2 | 2 | 86 → 229 | 90 | **100** | 13 | 31 | 0 |
| emotion-v7cv (CSS-var discipline) | 2 | 2 | 86 → 129 | 90 | **0** | 13 | 31 | 0 |
| emotion-v9 (naive) | 2 | 2 | 80 → 222 | 84 | **100** | 16 | 27 | 0 |

Observations:
- **Emotion inserts rules lazily, the first time each style variant mounts.** Examples: tab indicator/selected states (+13), Dialog/Modal/Backdrop (+31), and 1 rule per new progress value (0..100%). Each insertion is cached after that. Hover inserts nothing because `:hover` is in the already-inserted rule.
- AppBar `elevation` toggling on scroll caused **no** Emotion insertion. With `cssVariables:true`, Paper sets the shadow via an inline `--Paper-shadow` var (INFERRED from the 0 count; I did not read the source).
- **If we use CSS vars for anything dynamic, Emotion inserts 0 rules during scroll as well** (emotion-v7cv). It still pays 90 inserts plus runtime serialization at load and on first mounts.

### Chrome CDP Performance.getMetrics (cumulative; min–max of 3 runs; wall-time values are indicative only)

| app | load ScriptMs | load JSHeap KB | RecalcStyleMs during scroll (Δ) | RecalcStyleCount scroll Δ |
|---|---|---|---|---|
| pigment-v7 | 29.8–32.4 | ~5,280 | ~16–19 | 179 |
| pigment-v9p | 30.3–31.8 | ~5,260 | ~16–18 | 179 |
| emotion-v7 (naive) | 46.8–48.5 | ~7,200 | ~34–39 | 178 |
| emotion-v7cv | 45.2–53.6 | ~7,230 | ~16–20 | 178 |
| emotion-v9 (naive) | 48.0–49.4 | ~6,900 | ~47–56 | 179 |

### Chrome trace of scroll phase (168 frames; 2 runs each, counts identical across runs)

| app | UpdateLayoutTree | elementCount Σ | Layout | dirtyObjects Σ | Paint | PrePaint/Layerize | UpdateLayoutTree ms |
|---|---|---|---|---|---|---|---|
| pigment-v7 | 179 | 218–219 | 168 | 336 | 323 | 180 | 7.9–10.0 |
| pigment-v9p | 179 | 218 | 168 | 336 | 323 | 180 | 9.9 |
| emotion-v7 (naive, +100 insertRule) | 179 | 218 | 168 | 336 | 323 | 180 | 20.3–21.1 |
| emotion-v7cv | 178–179 | 218–219 | 168 | 336 | 323 | 180 | 13.2–14.6 |
| emotion-v9 (naive) | 179 | 218 | 168 | 336 | 323 | 180 | 22.8–24.3 |

**This matters for PLAN §4.** An `insertRule` makes Blink invalidate and rebuild the active stylesheet's RuleSet. The cost shows up as **time inside** the same number of style recalcs, not as more recalcs or more elements recalculated. The deterministic counters planned in §4 would score naive Emotion and Pigment as equal. INFERRED fix: add `cssomMutations` (insertRule/replace/style text and `<style>` node additions, per phase) as a deterministic counter in both engines. This spike shows it is exact and zero-variance across runs and engines. Optionally also count the `ParseAuthorStyleSheet` and `UpdateLayoutTree` durations as soft signals.

## Visual / correctness checks

In all builds, both engines computed the same values:
- "Get started" button: background `rgb(245,158,11)` (secondary), `border-radius: 9990px` (sx `borderRadius:999` × theme multiplier), `text-transform: none` (theme typography)
- AppBar: `rgb(29,78,216)`, `position: sticky`

No page errors. The only console error is a favicon 404. Theme `styleOverrides` and `variants` compiled fine because they are static. The `ownerState` callbacks the docs warn about were not used.

## Recommendations for the plan (INFERRED unless noted)

1. **The "MUI everywhere" decision is viable with zero runtime** if we pin one of these tested-good combos:
   - (a) **MUI 7.3.11 + Pigment 0.0.30 + Vite 6.4.4**: no patches, documented path. CONFIRMED builds and runs.
   - (b) MUI 9.0.1 + Pigment 0.0.30: unpatched, but a stale v9 patch release.
   - (c) MUI 9.5.0 + Pigment 0.0.31 with a `patch-package` patch for TouchRipple. Every MUI upgrade would need re-checking.

   I'd pick (a) and lock it with exact versions plus `npm ci`. Vite 8 works with `--legacy-peer-deps` but is outside the peer range. Prefer Vite 6.4.4 unless other plan parts need Vite 8.
2. **Add build gates:**
   - fail if the built JS contains `data-emotion`, `insertRule`, `@emotion/cache` or `stylis`
   - fail if the built CSS contains `null` or `undefined` values. This catches the silent dynamic-sx miscompile (CONFIRMED that it occurs).
   - lint/codemod rule: no non-literal values in `sx`/`styled`; dynamic values must go through CSS vars in `style`
3. **Add a CSSOM-mutation probe to §4 measurement.** It runs in Chromium and WebKit, and the expected value for a Pigment build is 0 in every phase. Existing work counts do not detect CSS-in-JS rule-injection cost (CONFIRMED in Chromium traces).
4. **Even in an Emotion fallback, the CSS-var discipline removes all scroll-time insertions** (emotion-v7cv: 0 during scroll). What remains is the cost at load and first mount: 90 inserts, ~+16 ms script, ~+2 MB heap and +27 kB gzip JS.
5. Risk register:
   - Pigment is still 0.0.x alpha, with one release in ~20 months
   - MUI v9 regressed Pigment compatibility within one minor release and nobody had reported it
   - The `@pigment-css/react` dependency on `@mui/system ^6` drags a second `@mui/system` copy into `node_modules` (`npm ls`: 6.5.0 next to 9.5.0). The bundle was not affected.

## Not done / limits

- No dev-server or HMR testing. SSR, RTL and the Next.js plugin were not tested.
- Only Button, Dialog, AppBar, Tabs, Card, Typography and Box were exercised. Select, Tooltip, Autocomplete, Menu and the transitions with `theme.motion` were not built under Pigment. Issue #46592 "Pigment + Mui Select does not compile" is open as of 2025-07-24.
- Wall-time figures come from a single dev Mac, 3 runs, headless Chrome. Treat them as directional only. The counts are exact.
