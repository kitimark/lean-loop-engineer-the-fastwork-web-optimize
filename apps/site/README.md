# @fw/site

Vite 8.3.4 + React 19.3.1 + MUI 9.5.0 (Emotion 11.14), prerendered. Placeholder content only (no site text or assets).
Spec: `docs/plan/PLAN.md` section 6, `research/kickoff/09-mui-zero-runtime/`.

## Commands (from `apps/site`)

| Command | What |
|---|---|
| `pnpm build` | `node scripts/build.mjs --engine aot` -> `dist/aot/` (default engine) |
| `pnpm build:runtime` | plain Emotion SSR -> `dist/runtime/` (negative control) |
| `pnpm census` | style-injection census on both builds (`--engine aot\|runtime`, `--runs N`, `--query "?fw=..."`, `--chrome PATH`, `--json FILE`; `CENSUS_VERBOSE=1` prints each missed style) |
| `pnpm test` | Vitest, flag resolver |
| `pnpm typecheck` | `tsc --noEmit` |

## How the AOT build works

1. Client bundle (Vite) and SSR bundle (Vite `ssr`) are built; the SSR bundle's `prerender()` runs in Node.
2. One `createCache({ key: 'mui' })` + `createEmotionServer` (sets `cache.compat`, so no inline tags) renders the home page and
   `src/Census.tsx` (every MUI component and state the site uses; overlays with `disablePortal`, open and `keepMounted` closed;
   every variant of every registered part).
3. `extractCriticalToChunks(home + census)` gives the CSS; it is written to `mui.[hash].css` as
   `@layer reset, mui, parts, flags; @layer mui{ theme variables + rules }` (the theme's `disableStyleSheetGeneration` is on, so MUI's
   `<Global>` variable sheet is emitted statically instead).
4. `ids` = **every** id in `cache.inserted`, written to `emotion-ids.json` and inlined as `<script type="application/json" id="fw-emotion-ids">`.
   The client sets `cache.inserted[id] = true` for all of them before `hydrateRoot`.
5. Build gates (`build-info.json`): no `<style>`/`data-emotion` in the HTML, ids > 0, no `null/undefined/NaN` in the CSS, layer order first.

Findings while building (all CONFIRMED by running it):
- **Intermediate rules.** `styled(Wrapper)` inserts its own rule whose class is merged into the child's and never appears in the HTML.
  The extractor drops those (id not in the HTML), so a client with only the HTML-matched ids still called `cache.insert` 8 times
  on first open of Dialog/Menu/Drawer. Fix: emit CSS only for HTML-matched rules but mark **all** inserted ids.
- **`Tab` outside `Tabs` throws** in 9.5.0 (`RovingTabIndexContext is missing`), so PLAN S7's "Tab buttons in a plain tablist" does not work;
  the home page uses `ButtonBase role="tab"`; `Tabs`/`Tab` stay in the census. S7 needs a wording fix.
- `disableStyleSheetGeneration` is a real ThemeProvider prop but missing from the typings (cast in `src/Root.tsx`).
- Default colour-scheme selector is `media`, so nothing is written on `<html>` (census records `html-attribute` events: none).
- MUI's default `xs..xl` media are removed through theme defaults (`src/theme.ts`): `Toolbar` dense + `disableGutters`,
  `Dialog maxWidth={false}`, `MenuItem dense`, `Tabs allowScrollButtonsMobile`. Parts that need width-dependent looks use CSS
  Modules with conditions from `src/breakpoints.ts`. The census asserts it (`scripts/media-check.mjs`): every `@media` in the built
  CSS must be in `breakpoints.gen.json` (currently an empty placeholder, so none are allowed) or in `src/mui-internal-media.json`
  (MUI feature queries `print`, `(hover: hover)`, `(hover: none)`, `(forced-colors: active)`, which no theme option removes; reported
  separately, they need a lead decision against the original's inventory).

## Registry and flags (`src/registry/`)

- `src/parts/<id>/part.json` is the source of truth (`hero.countdown`: variants `faithful`, `strip`). Presets: `src/registry/presets/*.json`.
- URL: `?fw=part:variant[@impl],...` (repeatable), `?preset=name`. Order: `fw` over `preset` over the default (head variant).
  Unknown ids/variants/impls and violated `requires`/`conflicts` give an error page (`mode: client-render`), never a fallback.
- Resolved once at load. If the config hash equals the prerendered one (`data-fw-config`), `hydrateRoot`; otherwise `createRoot`
  (`__fw.mode = 'client-render'`; a measured run should refuse that).
- `window.__fw = { config, configHash (FNV-1a 64 of sorted `part:variant@impl`), buildId, mode, hydrated, hydrationErrors,
  measureStartedAt, styleMisses, markMeasureStart }`. `markMeasureStart()` marks `fw:measure-start` and fires an event; call it after `hydrated`.
- Media conditions are read only through `src/breakpoints.ts` (reads the Lean-generated `breakpoints.gen.json`; `pnpm gen:breakpoints`, and every build byte-checks it).

## Census results (Mac Chrome 155 headless, 430x932, 3 runs each, zero variance)

Scripted scroll down and back (1 step per frame), then tab x2, menu, drawer, dialog (each opened and closed with Escape).
Hooks: `CSSStyleSheet` insertRule/deleteRule/replace/replaceSync/addRule, `CSSGroupingRule`, rule `style.setProperty`,
`adoptedStyleSheets` setter, MutationObserver on `<style>`/`<link>`/`<html>` attributes, and every `cache.insert`.

| Build | scroll | triggers | cache.insert after mark | verdict |
|---|---|---|---|---|
| `aot` (Emotion AOT) | 0 | 0 | 0 | PASS |
| `runtime` (plain Emotion SSR) | 0 | 69 | 23 | non-zero, as the negative control must be |

Build time (client + SSR + prerender, wall): aot about 0.5-3.3 s, runtime about 0.5-2.7 s (first runs 0.5-0.65 s warm; noisy, one Mac).
`mui.css` 223 kB raw (245 ids), prerendered HTML 20 kB.

### WebKit half (SPK-r), Playwright WebKit 27.2 on Mac (`--browser webkit`), 3 runs each, no variance

| Build | scroll | triggers | cache.insert after mark | verdict |
|---|---|---|---|---|
| `aot` | 0 | 0 | 0 | PASS |
| `runtime` | 0 | 69 | 23 | control caught |

Same hooks as Chrome (all JS-level, so they work in WebKit). Limits: desktop WebKit with a 430x932 viewport, no touch, no iOS toolbar,
no Safari/Simulator run; WebKit-internal style rebuild counts are not visible here (needs WKTR).
After the media/extractor fixes the Chrome results above are unchanged (aot PASS 0/0/0).

## Pure logic for a Lean spec + golden vectors

- Flag resolution `src/registry/resolve.ts` (Lean `Fw.Flags.resolve` covers defaults/override/ok; **not yet specified**: `?fw=` parsing,
  `?preset=` with `extends`, `@impl`, canonical config text and its hash, the hydrate-vs-client-render decision).
- `themeVariablesCss` serialiser (`src/theme.ts`), countdown text formatting (`src/parts/hero.countdown`), layer-wrap rule (`LAYER_ONLY` in `src/emotion.ts`).
