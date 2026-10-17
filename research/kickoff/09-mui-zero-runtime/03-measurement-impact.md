---
id: 2026-10-17-mui-measurement-impact
kind: note
title: "09.03 · How the styling engine changes what we measure, and how to prove MUI is neutral"
status: review
created: 2026-10-17
updated: 2026-10-17
authors: [agent:research-mui-measurement]
topics: [measurement, styling, mui, emotion, chromium, webkit, parity]
engines: [chromium, webkit]
builds: ["chromium:fcacb60bd396 (main 2026-10-16)", "webkit:77db40e2fa70 (main 2026-10-16)", "npm:@mui/material@9.5.0", "npm:@emotion/*@11.14.0", "npm:@emotion/sheet@1.4.0"]
links:
  notes:
    - docs/plan/PLAN.md (rev 3) §4, §6, §6.5, §6.6, R9, Q4
    - research/kickoff/02-site-anatomy-and-rewrite.md §5
    - research/kickoff/03-chromium-rendering-math.md §5.1, §7
    - research/kickoff/04-webkit-rendering-math.md §4.1, §7
    - research/kickoff/09-mui-zero-runtime/02-alternatives.md (option b+ "Emotion AOT")
  v1: ../fastwork-com-web-optimize/site-pretty (read only, snapshot)
---

# 09.03 · How the styling engine changes what we measure, and how to prove MUI is neutral

Kickoff research note, written 2026-10-17, after the user decided to use **MUI everywhere**. The plan's measurement
rests on engine work counts (PLAN §4.2). This note asks three things:

1. Which counts does a runtime CSS-in-JS engine (Emotion, under MUI 9.5.0) change in Blink and WebKit? The answer
   is traced through engine source.
2. What **styling neutrality** check should the plan run?
3. Which runtime rules must parts follow under MUI-everywhere, and how does the original Svelte site's static CSS
   compare?

**Status words.** **CONFIRMED** means a source line, doc or local grep cited next to the claim agrees.
**INFERRED** means my reading or design, not yet checked by a run. No engine run was made for this note. Every
magnitude below is INFERRED until the fixture in §5.4 runs.

**Pins.**

| Source | Pin | Short form below |
|---|---|---|
| Chromium | `chromium/chromium` at `fcacb60bd396` (main, 2026-10-16), the same pin as [03] | `cr:` + path under `third_party/blink/renderer/core/` |
| WebKit | `WebKit/WebKit` at `77db40e2fa70` (main, 2026-10-16), the same pin as [04] | `wk:` + path under `Source/WebCore/` |
| Emotion | `@emotion/sheet@1.4.0`, `@emotion/cache@11.14.0`, `@emotion/react@11.14.0` (npm tarballs, `src/`) | `em:` |
| MUI | `@mui/material@9.5.0`, `@mui/styled-engine@9.5.0`, `@mui/system@9.5.0` (npm tarballs, CJS build) | `mui:` |
| Original site | v1 snapshot `../fastwork-com-web-optimize/site-pretty/` (read only) | `A:` |

Sources were read through `gh api` (raw contents at the pin) and `npm pack` on 2026-10-17. `npm view` today gives
`@mui/material` `latest` 9.5.0 and `next` 10.0.0-alpha.0 (2026-10-12). **The v10 alpha still peer-depends on
`@emotion/react` and `@emotion/styled`** (CONFIRMED, `npm view @mui/material@10.0.0-alpha.0 peerDependencies`), so
no MUI release in sight removes Emotion.

---

## 0. Answer first

1. **A single CSSOM insertion after load is far more expensive than the count vector shows.** It is worst in
   WebKit, the target:
   - **WebKit.** `insertRule` into a style sheet that is already active clears the whole `Style::Resolver`. It then
     schedules a **full style rebuild of the document**:
     `CSSStyleSheet::didMutateRules` → `Scope::didChangeStyleSheetContents` → `scheduleUpdate(ContentsOrInterpretation)`
     → `clearResolver()` → `Reconstruct` → `Invalidator::invalidateAllStyle` → `scheduleFullStyleRebuild()`
     (CONFIRMED, §1.2).
   - **WebKit counts lane cannot see it.** The lane has no element counts before WKTR (PLAN §4.2, Q10). A full rebuild
     can look like one ordinary `RecalculateStyles` record that just takes longer.
   - **Blink, plain rule.** An `insertRule` of a plain rule takes a cheap, diff-based invalidation path. It still
     rebuilds the whole sheet's `RuleSet`, resets the scoped resolver and drops the matched-properties cache.
   - **Blink, layered rule.** MUI's `enableCssLayer` wraps **every** Emotion rule in `@layer mui {…}` (CONFIRMED,
     `mui:styled-engine/StyledEngineProvider/StyledEngineProvider.js` l.98-106). An `@layer` block is not a plain
     style rule, so Blink falls back to checking every selector of the old and new rule sets against the whole
     document. It also sets `kRuleSetFlagsAll`, which rebuilds the cascade-layer map, `@property` registry and
     font-face cache, then **marks the whole document for a font-update restyle and layout invalidation**
     (CONFIRMED in source, §1.1).
2. **Emotion also touches the DOM at hydration, even with SSR extraction.**
   - Creating the cache **moves** server-rendered `<style data-emotion>` tags (`appendChild` / `insertBefore`). Each
     move removes and re-inserts a style sheet.
   - `<Global>` (used by `CssBaseline`, `GlobalStyles` and the CSS-variables provider) inserts on mount **without
     checking `cache.inserted`**, unless it finds a matching server-rendered node, which it then moves.
   - Both happen once, at hydration. That is a WebKit full rebuild inside PLAN's "rest 6 s + first scroll" window
     (CONFIRMED in source, §1.3; cost INFERRED).
3. **Class-name churn is self-reinforcing.**
   - Every new `sx` or `styled` value produces a new hashed class, one new rule, and a class attribute change.
   - Emotion never removes rules, so the sheet only grows. Each later rebuild gets more expensive, which makes
     per-frame counts and costs **non-stationary** over a run (CONFIRMED that the sheet API has only
     `insert`/`flush`; growth effect INFERRED).
4. **The original site does no runtime style work of this kind.**
   - Its CSS is 4 linked files plus 3 inline `<style>` blocks in the server HTML.
   - Svelte scopes styles with compile-time `svelte-<hash>` classes.
   - Every JS chunk has **zero** `insertRule`, `adoptedStyleSheets`, `createElement('style')` or `.animate(` calls
     (CONFIRMED, local grep, §4).

   Arm A's style-sheet mutation count after load is therefore **0**. Parity of style work is reachable, but only if
   the MUI build is also static after first paint. That is option (b+) "Emotion AOT" in
   [09.02](02-alternatives.md).
5. **What the plan should add** (§2, §3):
   - A **styling neutrality** gate N0-N5:
     - zero sheet mutations, checked from both page and engine;
     - the same DOM-write census as the plain build;
     - equal style, layout, paint and layer counts against `impl: plain`;
     - a static style-shape census against arm A;
     - a hydration check.
   - Runtime rules S1-S13 that keep MUI static.
   - Fixture **K10 "sheet mutation"**, which puts numbers on §1 in both engines.

---

## 1. What runtime CSS-in-JS does inside the engines

### 1.1 Blink (Chromium)

**Path of one `insertRule` into an existing, connected `<style>` sheet** (Emotion's production "speedy" mode, §1.4):

| Step | What happens | Source (CONFIRMED) |
|---|---|---|
| 1 | `CSSStyleSheet::insertRule` parses the rule, opens a `RuleMutationScope` and calls `StyleSheetContents::WrapperInsertRule` | `cr:css/css_style_sheet.cc` l.430-471 |
| 2 | `WillMutateRules()`: if the contents are not shared, `contents_->ClearRuleSet()`. **The whole sheet's `RuleSet` is discarded**, and the next `EnsureRuleSet` re-adds every rule of the sheet (`AddRulesFromSheet`) | `css_style_sheet.cc` l.234-249; `cr:css/style_sheet_contents.cc` l.903-930 |
| 3 | `DidMutate(kRules)`: `StyleEngine::SetNeedsActiveStyleUpdate(tree scope)` and `StyleResolver::InvalidateMatchedPropertiesCache()`. **The matched-properties cache is dropped for the whole document**, so later recalcs miss it | `css_style_sheet.cc` l.251-283 |
| 4 | At the next lifecycle update, `StyleEngine::UpdateActiveStyleSheets` (trace slice `StyleEngine::updateActiveStyleSheets`, categories `blink,blink_style`) → `ApplyRuleSetChanges` → `CompareActiveStyleSheets` | `cr:css/style_engine.cc` l.672-680, l.3154-3168 |
| 5 | Same sheet, different `RuleSet` → **`kActiveSheetsChanged`**, not "appended" | `cr:css/active_style_sheets.cc` l.75-144 |
| 6 | If a `RuleSetDiff` exists, only the changed rules are checked. **It exists only for plain style rules.** An `@layer` block, `@keyframes` or `@import` makes the diff "unrepresentable", and then every selector in the old and new rule sets is checked | `cr:css/rule_set_diff.h` l.18-40; `style_sheet_contents.cc` l.292-298 |
| 7 | `InvalidateForRuleSetChanges` walks **every element of the tree scope** and matches it against the changed rule sets. The code comment notes false positives, for example "someone added a single new rule to a style sheet, causing a new RuleSet to be created that also contains all the old rules" | `style_engine.cc` l.2551-2582, l.2896-2938 |
| 8 | `kActiveSheetsChanged` → `scoped_resolver->ResetStyle()` and all sheets of the scope are re-appended; `global_rule_set_->MarkDirty()` re-aggregates rule features | `style_engine.cc` l.3211, l.3222-3236, l.3305-3315 |
| 9 | **If the changed rule sets contain cascade layers and the change is `kActiveSheetsChanged`, the flags become `kRuleSetFlagsAll`** ("existing layer ordering may be changed, which requires rebuilding all at-rule registries and full document style recalc"). That rebuilds the cascade-layer map, drops the MPC again, clears the `@property` registry and rebuilds the font-face cache, then calls `FontFaceInvalidated` | `style_engine.cc` l.152-200 (`GetRuleSetFlags`: `HasCascadeLayers()` → `kLayerRules`), l.3171-3181, l.3243-3260, l.3274-3285, l.3322-3325 |
| 10 | `FontFaceInvalidated` → `FontsNeedUpdate` → `MarkFontsNeedUpdate`; at the next update `InvalidateStyleAndLayoutForFontUpdates` calls `MarkSubtreeNeedsStyleRecalcForFontUpdates` on `<html>` and `InvalidateSubtreeLayoutForFontUpdates` on the `LayoutView` (trace slices with those names) | `style_engine.cc` l.1410-1454; `cr:css/css_font_selector.cc` l.159-161 |

**What the Chromium counts would show (INFERRED, to be checked in K10):**
- **Plain rule** (no layers): `UpdateLayoutTree` `elementCount` rises only by the elements that match the new
  selector, usually just the element whose class changed. The real cost is uncounted: the sheet's `RuleSet` rebuild,
  feature re-aggregation and a cold MPC. **Counts nearly flat, time up.** That is the case PLAN §4.3 calls dangerous
  for class W.
- **Layered rule** (MUI `enableCssLayer`): `elementCount` approaches every element matched by any MUI rule. On top
  of that come the font-update marks over the whole document and `Layout` `dirtyObjects` for text. Counts go up
  sharply.
- **`@keyframes` insertion** (MUI's ripple and any `keyframes`` ` call): unrepresentable diff, plus
  `ScopedStyleResolver::KeyframesRulesAdded` (`style_engine.cc` l.3213-3215).

**`<style>` text nodes instead of `insertRule`** (Emotion development mode, or any non-speedy sheet):
- A new `<style>` appended **after** all other sheets → `kActiveSheetsAppended`: only the new sheet's rules are
  checked, with no resolver reset and no layer escalation (that only applies to `kActiveSheetsChanged`).
- A new tag inserted **before** others (MUI's `injectFirst` insertion point, or `prepend`), a text change inside an
  existing tag (`StyleElement::ChildrenChanged` re-creates the sheet), or a moved tag → `kActiveSheetsChanged`.
- Identical text can reuse a parsed `StyleSheetContents` through `text_to_sheet_cache_` (`style_engine.cc`
  l.1229-1329). That saves parsing, not invalidation.

### 1.2 WebKit (Safari, the target)

| Step | What happens | Source (CONFIRMED) |
|---|---|---|
| 1 | `CSSStyleSheet::insertRule` → `RuleMutationScope(this, RuleInsertion, keyframes?)` → `didMutateRules` | `wk:css/CSSStyleSheet.cpp` l.373-392, l.644-671 |
| 2 | **Cheap path only if the sheet is not yet active** (`!scope.activeStyleSheetsContains(*this)` and no copy-on-write clone): a `@keyframes` rule is added straight to the resolver; anything else marks only the *active set* dirty | `CSSStyleSheet.cpp` l.234-249 |
| 3 | Otherwise `scope.didChangeStyleSheetContents()` → `scheduleUpdate(ContentsOrInterpretation)`, which **immediately calls `clearResolver()`** (the whole `Style::Resolver` is dropped, along with the document's `m_matchResultCache`) | `CSSStyleSheet.cpp` l.251-259; `wk:style/StyleScope.cpp` l.168-176, l.726-760 |
| 4 | `updateActiveStyleSheets(ContentsOrInterpretation)`: only an `ActiveSet` update may use `analyzeStyleSheetChange`; a contents change is **`Reconstruct`** | `StyleScope.cpp` l.585-589 |
| 5 | `Reconstruct` → `Invalidator::invalidateAllStyle` → `document().scheduleFullStyleRebuild()` | `StyleScope.cpp` l.608-619; `wk:style/StyleInvalidator.cpp` l.654-664 |
| 6 | New sheets added through the active set: appended at the end → `Additive` (selective invalidation); inserted in the middle → `Reset` (`resetAuthorStyle()` and every author sheet re-added); removed or re-ordered → `Reconstruct` | `StyleScope.cpp` l.498-537, l.625-650 |
| 7 | Even `Additive` turns into a full rebuild if an added sheet holds any top-level rule that is not a `StyleRule` (only `@media` and nesting are looked into). **`@layer` blocks, `@keyframes`, `@font-face` and `@property` all count** | `StyleInvalidator.cpp` l.50-98 (`shouldDirtyAllStyle`) |
| 8 | A `<style>` whose text changes is re-created (`InlineStyleSheetOwner::childrenChanged` → `createSheet`), with a parsed-contents cache keyed on text | `wk:dom/InlineStyleSheetOwner.cpp` l.42-90, l.137-175 |

**Consequence (CONFIRMED path, INFERRED cost).** After hydration, Emotion's speedy sheet is active, so **every frame
with at least one insertion costs a full-document style rebuild and a resolver rebuild from every author rule**
(about 2,200 rule blocks in the original's CSS, §4, plus MUI's). Insertions within one task coalesce into one
pending update (one timer, `StyleScope.cpp` l.741-749), so the cost is per frame, not per rule.

**What the WebKit counts would show (INFERRED):**
- Inspector `Timeline`: perhaps **no extra `RecalculateStyles` record**, because a scroll-linked frame already
  restyles. The record is longer, but the counts lane does not read durations. WKTR's `lastStyleUpdateSize` would
  jump to about the document's element count, but WKTR is not available until the M3 spike (PLAN §4.2, Q10).
- Any style-difference that needs layout after the rebuild adds `Layout` records. A rebuild that changes nothing
  needs none.
- So **the WebKit Phase A count vector is blind to this whole mechanism.** It has to be detected directly
  (neutrality checks N0 and N1).

### 1.3 Emotion and MUI behaviour that triggers the paths above

| Trigger | When | Engine path | Source (CONFIRMED) |
|---|---|---|---|
| **Speedy `insertRule`** into one tag (a new tag only every 65,000 rules); production default is `speedy = !isDevelopment` | any style id not yet in `cache.inserted` | Blink §1.1 rows 1-10; WebKit §1.2 rows 1-5 | `em:sheet/src/index.ts` l.79, l.113-163 |
| **Development mode: one `<style>` per rule**, as a text node | dev builds only (never measured, PLAN §6.5 rule 5) | appended → cheap in Blink; WebKit full rebuild if it is `@layer` | same file l.116-160 |
| **SSR tags moved at cache creation**: for key `css`, every `style[data-emotion]` is `document.head.appendChild`-ed; each cache also `hydrate()`s its own SSR tags, and `_insertTag` does `container.insertBefore(tag, before)` | first client render (MUI creates the cache when its module loads or on first render) | remove and re-insert of a sheet → Blink `kActiveSheetsChanged` (with layers: `kRuleSetFlagsAll`); WebKit `Reconstruct` → full rebuild | `em:cache/src/index.ts` l.62-86, l.100-115, l.252; `em:sheet/src/index.ts` l.91-109 |
| **`<Global>` inserts with `shouldCache = false`**, bypassing `cache.inserted`; with a matching SSR node it instead re-keys and moves that node (`setAttribute` + `hydrate`); a new style name later means `flush()` (tag removal) and re-insert | mount of `CssBaseline`, `GlobalStyles`, the CSS-vars provider; any change to its serialized styles | removal/insertion as above | `em:react/src/global.tsx` l.89-138 |
| **CSS-variables provider**: renders `GlobalStyles` with the theme's variable sheet unless `disableStyleSheetGeneration`; a layout effect writes the color-scheme class or attribute on `<html>` when `colorSchemeSelector` is not `'media'` | hydration | `<Global>` row; root class/attribute change → root-level invalidation | `mui:system/cssVars/createCssVarsProvider.js` l.170-208, l.248-262 |
| **`enableCssLayer`**: cache key `mui`; every insert wrapped in `@layer mui {…}`; the source notes this getCache path is "for client-side apps only" | every insertion | the layered path: Blink row 9-10, WebKit row 7 | `mui:styled-engine/StyledEngineProvider/StyledEngineProvider.js` l.71-109 |
| **Lazy ripple**: `touchstart` on any `ButtonBase` → `useLazyRipple.mount()` (React `setState` re-renders the button) → `TouchRipple` mounts (its styled root and the `enter`/`exit`/`pulsate` `keyframes` inserted on first use) → `computeRippleState` calls **`getBoundingClientRect()`** → after `DELAY_RIPPLE` = 80 ms a ripple `<span>` mounts; `touchmove` stops it | the first finger-down on any button, including a swipe that starts on a CTA | forced layout if dirty; first-use `@keyframes` insertion (§1.1 and §1.2 keyframes rows); React commit | `mui:material/ButtonBase/TouchRipple.js` l.23, l.72-90, l.115-140, l.335-380; `ButtonBase/ButtonBase.js` l.161, l.215, l.233-235; `useLazyRipple/useLazyRipple.js` l.24-74 |
| **Transition components**: `reflow = node => node.scrollTop` (a forced layout) in Fade, Grow and Slide; Grow reads `clientHeight`; Slide calls `getBoundingClientRect` twice and writes inline `transform`/`transition`; Collapse reads `clientHeight`/`clientWidth` and writes `position` and the transition | every enter/exit | forced layout + inline style writes from JS | `mui:material/transitions/utils.js` l.14; `Fade/Fade.js` l.71-120; `Grow/Grow.js` l.77-155; `Slide/Slide.js` l.44-62, l.145-207; `Collapse/Collapse.js` l.171-254 |
| **Tabs indicator**: `getBoundingClientRect` on the tabs and the active tab, then `left`/`width` styles | value change, resize | rect read + layout-property animation | `mui:material/Tabs/Tabs.js` l.275-278, l.338-396 (and [02 §5.2]) |

### 1.4 Class-name churn

Under Emotion the class is a hash of the serialized styles:
- An `sx={{ transform: \`translateY(${y}px)\` }}` or `styled(…)(({p}) => …)` with a changing value produces a new
  class name for each distinct value.
- Per new value: (a) one `insertRule` (§1.1 and §1.2), (b) a React commit that rewrites `className`, (c) a class
  attribute change. In Blink, (c) schedules class invalidation sets for the removed and the added class
  (`cr:css/style-invalidation.md`, cited in [03 §5.1]). In WebKit it goes through class-change invalidation.
- Values that repeat (a periodic animation) re-use cached ids, so (a) stops after one period, but (b) and (c)
  continue on every frame.
- Values that never repeat (scroll position, time) **insert forever**. The sheet only grows (the `@emotion/sheet` API
  has `insert` and `flush`, nothing in between; `em:sheet/src/index.ts` l.113-175). So the per-frame rebuild cost
  grows with run length (INFERRED). That breaks two of the plan's assumptions: per-frame dominance screening
  (PLAN §4.3, condition 1) and run-length-independent counts (V-i).

Theme context changes (a new theme object, a nested `ThemeProvider`, `useMediaQuery` flips) re-render every MUI
consumer. That costs script time even when no class changes. Script ms are "measured, not modelled" (PLAN §4.2), so
this shows up only in the timing lane (INFERRED).

### 1.5 Effect on each count family (PLAN §4.2 table)

| Family | Chromium | WebKit (Phase A, no WKTR) | Visible in the count vector? |
|---|---|---|---|
| Script | rAF count unchanged; React commits and Emotion serialization add JS | same | **No** (script ms are measured, not counted) |
| Style | `UpdateLayoutTree` passes: maybe +0 (it piggybacks on a frame that already restyles); `elementCount`: small (plain) or about the whole document (layered, or font-update marking) | `RecalculateStyles` count maybe +0; duration up; scope = whole document | Chromium: partly. **WebKit: no** |
| Layout | layered path: font-update layout invalidation → `dirtyObjects` up; forced layouts from ripple, Transition and Tabs reads (with JS stack) | `Layout` records from rebuild style diffs and from forced reads | yes (forced layouts are counted exactly, PL5) |
| Paint / raster | only when the restyle changes something visual | same | yes, indirectly |
| Layers | ripple spans, Transition `will-change` and Portals can add layers | same | yes (layers ±0 in PL5) |
| **Sheet mutations** | trace slices `StyleEngine::updateActiveStyleSheets`, `StyleEngine::scheduleInvalidationsForRuleSets`, `StyleEngine::InvalidateStyleAndLayoutForFontUpdates` | Inspector `CSS.styleSheetAdded/Removed/Changed` events (`JavaScriptCore/inspector/protocol/CSS.json`, CONFIRMED event names) | **not yet a family: add it (§2)** |

---

## 2. The styling neutrality check (proposal for PLAN §4.2, §6.5, §6.6)

**Purpose.** Show that "MUI" in a `faithful` part adds **no engine work** compared with (i) the original (arm A) and
(ii) the same part built with plain CSS Modules (`impl: plain`). Then MUI is not a confound, and PL5/PL6 compare
mechanisms, not styling engines. All thresholds are proposals (INFERRED) and are re-set once from the M2 pilot, like
the PL5 bands.

**Windows.** W-load = navigation to `__fw.hydrated`. W-rest = `__fw.hydrated` to `markMeasureStart()`, including the
6 s rest. W-measure = `markMeasureStart()` to end of scenario. W-trigger = an overlay or interaction scenario's own
window, starting at its trigger.

| Check | What | How | Gate |
|---|---|---|---|
| **N0 sheet-mutation census, page side** (every counts-lane run, both engines) | count of style-sheet mutations | an init script injected before any page script (both arms) wraps `CSSStyleSheet.prototype.{insertRule, deleteRule, addRule, removeRule, replace, replaceSync}`, `CSSGroupingRule.prototype.{insertRule, deleteRule}`, `CSSKeyframesRule.prototype.{appendRule, deleteRule}`, the `selectorText` setter, the `adoptedStyleSheets` setters, and `CSSStyleDeclaration.prototype.setProperty`/`removeProperty`/`cssText` **only when `this.parentRule != null`** (rule-level edits; inline `element.style` writes by MotionClock stay allowed). One `MutationObserver` on `document` (subtree, childList, characterData, attributes `media`/`disabled`/`href`/`rel`) catches `<style>` and `<link rel=stylesheet>` adds, removes, **moves** and text edits anywhere in the tree. A backstop hash of `[sheet count, cssRules.length per sheet]` is taken at each window edge | **W-measure: 0 (exact). W-rest: 0. W-trigger: 0.** W-load: equal to arm A's (which is 0, §4) or recorded as a class X delta. This replaces and widens the plan's `STYLE-INJECTION` guard, which today wraps only `insertRule`/`replace` and watches only `<head>` |
| **N1 sheet-mutation census, engine side** (catches native paths the wrappers miss) | Chromium: number of `StyleEngine::updateActiveStyleSheets`, `StyleEngine::scheduleInvalidationsForRuleSets`, `StyleEngine::InvalidateStyleAndLayoutForFontUpdates` slices. WebKit: number of `CSS.styleSheetAdded/Removed/Changed` events | Chromium: `blink,blink_style` categories in the counts-lane trace (cheap; the slices fire only when work is pending, `style_engine.cc` l.672-680). WebKit: `CSS.enable` over iwdp **in attribution runs only** (enabling the CSS domain may perturb, INFERRED). Font loads are moved before W-rest, since every font is preloaded from `snapshot/` | W-measure and W-rest: **0**, both arms. A non-zero count on arm A is a harness finding and is recorded, not gated |
| **N2 DOM-write census parity** (counts lane) | per frame: `class` attribute changes, `style` attribute changes, childList mutations, per anchor | the same `MutationObserver`, keyed by `data-fw` anchor | `faithful-mui` = `faithful-plain`, **exact per frame**; and equal to arm A where `parity.json` maps the write (a Svelte `class:` toggle ↔ a React className flip). Any extra className rewrite per frame means churn (§1.4) |
| **N3 work-count parity, plain vs MUI** (counts lane, the same scenarios as PL5) | Chromium: `UpdateLayoutTree` passes and `elementCount`, `Layout` passes and `dirtyObjects`, forced layouts, `Paint`, raster-invalidated px, layers. WebKit: `RecalculateStyles`, `Layout`, `Paint` clip area, `LayerTree` count; `lastStyleUpdateSize` once WKTR exists | the `impl: plain \| mui` arm pair, same flags otherwise | passes, forced layouts and layers **exact**. `elementCount`/`dirtyObjects`: `|mui − plain| ≤ max(2, w)`, where w is the number of MUI wrapper elements inside the invalidated subtree, taken from the `parity.json` wrapper map (MUI adds `Paper`, `Backdrop`, `ButtonBase` spans and Portal roots). Paint/raster: the PL5 band. **Until WKTR exists, a style-affecting diff cannot pass N3 on WebKit by counts alone**, which matches PLAN Q10 |
| **N4 static style-shape census** (once per build, both arms; feeds `ρ_page` and the K fixtures) | the engine-facing shape of all author CSS after load: number of style rules; selectors bucketed by rightmost compound (id / class / tag / attribute / universal / pseudo); custom properties declared on `:root` and on `*`/`html`/`body`; registered `@property` (`inherits: false` vs `true`); `@layer` count and depth; `@keyframes`; `@font-face`; `@media` count and how many match at each viewport | read `document.styleSheets` (CSSOM walk) at the end of W-rest; the same script on A and R | rule count and `:root` custom-property count **within ±10 % of arm A**, or the difference goes into the K fixtures as a parameter (PLAN §4.4 already passes the original's rule count and custom-property count as parameters) and is flagged for the PL6 timing check. Universal-selector rules added by MUI's baseline: listed by name, each one justified |
| **N5 hydration neutrality** (counts lane, W-load) | the SSR class and style attributes vs the post-hydration DOM; Emotion cache misses at hydration | snapshot the SSR HTML's `class`/`style` for every anchor; diff after `__fw.hydrated`. In measurement builds, wrap `cache.insert` and count calls whose id is not in the AOT census ([09.02] (b+)) | **0 attribute diffs; 0 cache misses; 0 style-tag moves** (N0's MutationObserver sees moves). React does not reliably patch attribute mismatches in production (INFERRED from React's hydration contract; verify in S-AOT), so a class mismatch would sit unseen until the next re-render, which then causes churn |

**Where it plugs in.**
- **PLAN §4.2.** Add the "Sheet mutations" family (N0/N1) to every count vector, and make it part of the "declared
  complete" vector lint for class W. A diff that changes styling-engine configuration (theme, layers, cache options)
  is class SM until K10 has priced it.
- **PLAN §6.6.**
  - Add to PL5: "sheet mutations = 0 in W-measure and W-rest (exact), DOM-write census equal to the plain build
    (exact)".
  - Run N3 on every part whose `impl` is `mui`.
  - N4 runs at PL2 time, because it is a property of the build, not of a scenario.
- **PLAN R9.** The mitigation becomes "N0-N5 + K10" in place of "Q4 scope + the injection guard".
- **Failure handling.** A failed N0/N1 is an **incident against the part, never a result** (in the spirit of the
  plan's rule that an output failing its schema is an incident). A failed N3 makes the part `faithful-with-delta`
  with the measured delta recorded in the validity table, as PLAN §6.2 already allows.

---

## 3. Runtime rules for parts under MUI-everywhere (proposal to replace PLAN §6.5 rule 6)

These extend rules 1-5 of §6.5 (which stay). Each rule cites the mechanism it prevents. Lint means an ESLint or
ast-grep rule in `apps/site`. Guard means N0-N5.

| # | Rule | Prevents | Enforced by |
|---|---|---|---|
| S1 | **Static MUI styling only.** No `sx` prop, no `styled()` with prop or function interpolation, no Emotion `css` prop and no `css`/`keyframes` call in `src/parts/**`. Parts style MUI through `className` and `slotProps.*.className` from CSS Modules in `@layer parts` (as in [09.02] §8) | runtime insertion and class churn (§1.1-§1.4) | lint (`no-restricted-syntax` on `sx=`, `styled(` with an arrow argument, `@emotion/*` imports); N0 |
| S2 | **Theme `styleOverrides`/`variants` must be enumerable.** Every `ownerState` combination used at runtime is in the AOT census; a function override may only branch on props whose values are listed in `part.json` | a census miss = a mid-session insertion | N5 cache-miss counter; S-AOT spike |
| S3 | **Per-frame motion only through `MotionClock` writers.** Writes go to `element.style.setProperty('--var', …)` on the *consuming* element (not an ancestor, so the inherited-custom-property subtree restyle stays as small as in the original), or to `transform`/`opacity` inline, or through WAAPI / scroll timelines. Never React state, props, context or className | React commits, churn | PLAN §6.5 rules 1-2; N2 |
| S4 | **Discrete state flips may re-render** (tab change, menu open, the avatar swap the original does with `{#if}`), but **must map to class names that exist in the static CSS**. A flip may change classes; it may not create rules | insertion on a flip | N0 in W-trigger; N2 per frame |
| S5 | **No MUI Transition components on scroll-linked or always-mounted paths** (`Fade`, `Grow`, `Slide`, `Collapse`, `Zoom`, and anything passing a `TransitionComponent`). Overlays replace `slots.transition` with a component that toggles a class whose keyframes restate the original's | forced layout `node.scrollTop`, rect and `clientHeight` reads, inline style writes from JS (§1.3) | lint: `no-restricted-imports` for those modules under `src/parts/**`; overlays checked at PL4 in their own scenario |
| S6 | **Ripples off theme-wide.** `components.MuiButtonBase.defaultProps = { disableRipple: true, disableTouchRipple: true }`, with focus styles restated in CSS | a touchstart re-render, rect read and first-use `@keyframes` insertion at the start of a finger swipe (§1.3). This matters for the Simulator finger-drag profile and the device | theme unit test; N0 in the finger-replay scenario |
| S7 | **Tabs and other measuring widgets**: hide the built-in indicator (`slotProps.indicator`) and draw the original's indicator in CSS; no `variant="scrollable"` scroll buttons; no `Popper`/`Tooltip`/`Autocomplete` in scroll paths | rect reads + `left`/`width` animation ([02 §5.2]) | lint + PL5 forced-layout count (exact) |
| S8 | **One static theme, created at module scope.** No theme objects built in render, no nested `ThemeProvider` that creates a new object, no runtime mode switching. If `cssVariables` is used: `disableStyleSheetGeneration` + the variable sheet emitted into the static CSS at build; `colorSchemeSelector: 'media'` or a single scheme, so no class or attribute is written on `<html>` at hydration | Global insertion, root invalidation, re-renders of every consumer (§1.3) | N0/N1 in W-load and W-rest; N5 |
| S9 | **No Emotion `<Global>` at runtime.** That includes `CssBaseline`, `ScopedCssBaseline`, `GlobalStyles` and `enableColorScheme`. Global CSS is part of the static CSS file in `@layer reset` | `<Global>` bypasses `cache.inserted` and moves or flushes tags (§1.3) | lint; N0 |
| S10 | **No JS media queries for styling.** `useMediaQuery` is not used for layout or look. Breakpoints live in CSS. (It re-renders on change; on iOS the toolbar step 775↔815 flips any height query) | React commits on resize; SSR/client mismatch | lint (allow-list for behaviour-only uses) |
| S11 | **Emotion configuration is fixed and measured once:** production `speedy` (default), key `mui`, `enableCssLayer` on, layer order `@layer reset, mui, parts, flags` (from [09.02]); no `injectFirst`/`prepend` (a mid-list insertion is a WebKit `Reset` and a Blink `kActiveSheetsChanged`). The configuration is part of the build ID, and changing it is a class SM diff | an unpriced change to the styling engine | build-ID hash; K10 |
| S12 | **Overlays (`Dialog`, `Drawer`, `Menu`) are closed during scroll scenarios** and are mounted at load or kept mounted (`keepMounted`), so that opening one inserts no styles; `disableScrollLock` decided against the original's behaviour at PL4 | insertion and body `overflow`/padding writes at the trigger | N0 in W-trigger |
| S13 | **Fonts and typography**: the theme sets the original's families and metrics (no Roboto default), so no extra font lookups or fallback shaping | layout/paint differences masquerading as styling cost | PL1/PL3; N4 lists `@font-face` |

**What these rules do not cover.** MUI's extra DOM (wrappers, Portals) changes `elementCount` and PL0/PL1 anchors
whatever the styling engine does. That is handled by N3's wrapper allowance and the `parity.json` wrapper map, not
by rules.

---

## 4. The original Svelte site: static CSS, and how parity is reachable

**What arm A does (all CONFIRMED by local reads of `A:` on 2026-10-17):**

| Fact | Evidence |
|---|---|
| CSS is delivered as **4 linked stylesheets** in the server HTML: `app.DTmXyoED.css` (5,580 B), `DialogHeader.Qcgwm6ST.css` (21,876 B), `0.ChGpbVhU.css` (30,083 B), `2.gBuqKVzi.css` (274,057 B, 11,770 lines) | `grep '<link' A:index.html`; `wc` |
| plus **3 inline `<style>` blocks** in the HTML (site-specific rules for locale links and the CTA stack) | `grep '<style' A:index.html` |
| `2.gBuqKVzi.css`: about 1,980 `{` blocks (rules plus keyframe steps), 123 `@keyframes`, 83 `@media`, 4 `@property`, **0 `@layer`**; 26 distinct `svelte-*` scope classes (10 in DialogHeader, 4 in app) | `grep -c` on each file |
| **No runtime style-sheet API in any JS chunk**: 0 × `insertRule`, `adoptedStyleSheets`, `CSSStyleSheet`, `createElement("style")`; 0 × `.animate(` (no Svelte `transition:`/WAAPI); 21 × `setProperty` and 14 × `classList` (the per-frame writers) | grep over `A:_app/immutable/{nodes,chunks}/*.js` |
| 387 elements in the SSR HTML carry a `svelte-*` class | grep of `A:index.html` |

**How Svelte gets there (CONFIRMED, docs).** The compiler's `css` option: with `'external'` "the CSS will only be
returned in the `css` field of the compilation result", and "most Svelte bundler plugins will set this to
`'external'` and use the CSS that is statically generated". Scoping is the class `svelte-${hash(…)}` from `cssHash`
(https://svelte.dev/docs/svelte/svelte-compiler). SvelteKit's `inlineStyleThreshold` (default 0) merges small CSS
files into an inline `<style>` (https://svelte.dev/docs/kit/configuration). So arm A's style sheets are parsed during
load and never mutated. **Its per-frame style work comes only from class toggles, inline style and custom-property
writes, and CSS animations.** N0/N1 on arm A should read 0 after load. That is the first thing to check on Day 1-5
(M1, original first).

**Parity of style work: what has to match, and how.**

| Dimension | Arm A (Svelte) | R with MUI | How parity is reached |
|---|---|---|---|
| Sheet mutations after load | 0 (static) | 0 only with (b+) Emotion AOT + S1-S12 | N0/N1 exact |
| Sheet structure at load | 4 links + 3 inline | AOT `mui.[hash].css` + CSS Modules output + reset; in `@layer` | N4; load cost belongs to W-load (class X), not W-measure |
| Selector shape | `.x.svelte-abc` (compound, global `start-selling-*` classes) | `.Part_x__h` (CSS Modules) and `.mui-<hash>` / `.Mui*` (MUI) | per element both are class-keyed buckets; Blink invalidation sets and WebKit class-change invalidation key on class names, so the per-toggle invalidation scope matches when the toggled class and its descendant selectors are restated 1:1 (INFERRED; N3 checks it) |
| Cascade layers | none | `reset, mui, parts, flags` | static layers cost little per declaration (INFERRED). Their real risk is that any later mutation escalates to `kRuleSetFlagsAll` in Blink and a full rebuild in WebKit (§1), which N0 forbids |
| Rule count | about 2,200 blocks (about half of Platform's animation CSS is dead, [02 §2.6]) | MUI component defaults (later overridden) + restated rules | N4 within ±10 %, or as a K-fixture parameter; the plan's "inert stylesheet" option ([PLAN §6.1]) can top up a deficit |
| Root custom properties | the original's set (v1 measured custom-property restyle at 2.2× blank-page cost on WebKit, PLAN §4.3) | + MUI `--mui-*` variables if `cssVariables` is on | N4 counts them; prefer `cssVariables` off, or trimmed with MUI's skip option (INFERRED API; check in S-AOT), so the inherited set on every element stays near arm A's |
| Per-frame writers | 21 `setProperty` / 14 `classList` sites | MotionClock writers (S3), class flips (S4) | N2 exact per frame |
| Animations | 123 `@keyframes` declared statically; no WAAPI | restated keyframes in CSS Modules; no Emotion `keyframes` | N4 lists them; PL4 |

**Why the counts alone do not prove parity.** Per-element style cost depends on rule-set size, selector shape and
inherited custom properties, and none of these is a count (PLAN §4.3 "page factor"). Two builds can have identical
`elementCount` and still differ in ms. So N4 exists to keep the shape near arm A, and PL6 (timing parity) stays the
final check. `ρ_page` is fitted on arm A (M3). If N4 shows R's shape is materially different, R needs its own
`ρ_page`, or predictions for R are labelled `uncalibrated` (INFERRED).

---

## 5. What to change in the plan, and the spike that prices §1

### 5.1 Edits to PLAN (proposals)

1. **§0 and Q4.** Restate MUI-everywhere as "MUI components, styles compiled ahead of time; zero runtime insertion
   after first paint" ([09.02] (b+)), gated by N0-N5.
2. **§4.2 table.** Add the row "Sheet mutations": Chromium `updateActiveStyleSheets` / `scheduleInvalidationsForRuleSets`
   / font-update slices; WebKit `CSS.styleSheet*` events (attribution) + the page-side census (always).
3. **§6.5 rule 6.** Replace it with S1-S13 (§3). Keep the `impl: plain | mui` pair, now on **every experiment part**,
   because N3 needs it there.
4. **§6.6.** Add N0/N2 to PL5 (exact), N4 to PL2, and N5 to the M4 whole-page check.
5. **§11 R9.** Mitigation: "N0-N5 + K10 + S-AOT".
6. **§10.2.** Run N0/N1 on **arm A** in M1, to confirm the 0 baseline before any rewrite exists.

### 5.2 Fixture K10 "sheet mutation" (extends the K1-K9 suite of [04 §9]; our own page, no Fastwork CSS)

A page with N elements (parameter, default about the original's element count) and R static rules (parameter,
default about 2,200, per N4). Each frame applies one treatment, at 60 steps in each engine:

| Arm | Per-frame treatment | Predicted from source (INFERRED until run) |
|---|---|---|
| k10-0 | none (baseline) | — |
| k10-var | one custom property written on one leaf element | small restyle (the S3 path) |
| k10-plain | `insertRule('.c-<n>{…}')` into an active `<style>` + class flip on one element | Blink: small `elementCount`, `updateActiveStyleSheets` = 1/frame; WebKit: full rebuild (`lastStyleUpdateSize` ≈ N under WKTR) |
| k10-layer | the same, wrapped in `@layer mui{…}` | Blink: `elementCount` ≈ elements matching the sheet, plus font-update marks over the document and layout dirtiness; WebKit: full rebuild |
| k10-kf | `insertRule('@keyframes k<n>{…}')` | Blink: unrepresentable diff + keyframes path; WebKit: active sheet → full rebuild |
| k10-append | a new `<style>` appended at the end of `<head>` (plain / layered) | Blink: `kActiveSheetsAppended`; WebKit: `Additive` (plain) vs full rebuild (layered) |
| k10-move | an existing `<style>` re-appended (the Emotion hydration move) | Blink: `kActiveSheetsChanged`; WebKit: `Reconstruct` |
| k10-grow | k10-plain for 600 frames | per-frame cost rising with sheet size (non-stationarity, §1.4) |

Read in Chromium: `elementCount`, `dirtyObjects`, the three N1 slices. Read in WebKit: `RecalculateStyles` count and
duration (timing lane), `Layout` count, and `lastStyleUpdateSize` once WKTR exists (M3). On the device (calibration
session): k10-0 vs k10-layer vs k10-plain, once, to price "one insertion per frame" in ms on the iPhone.

**Budget.** 0.5 agent-day to write it, run in the M3 WKTR spike window (fits the plan's "1-day WKTR spike"), plus
about 2 minutes of device time in the first calibration session. Its result decides whether S11's `enableCssLayer`
stays: if k10-layer is much worse than k10-plain and N0 can ever be non-zero, a layer-free configuration is safer.
With N0 = 0 enforced, layers cost nothing at run time (INFERRED).

### 5.3 Add to Appendix B

- **SPK-q (styling neutrality baseline).** N0/N1 on arm A, in both engines, in W-load, W-rest and W-measure. Pass
  when every value in W-rest and W-measure is 0 (expected from §4). Day 2-5, alongside SPK-j.
- **S-AOT** (from [09.02] §8), with N5 as its pass condition: 0 cache misses and 0 style-tag moves at hydration for
  Button, Dialog, Menu, Tabs and Drawer.

---

## 6. Open questions and risks (all INFERRED)

1. **Engine-side detection on the iPhone itself.** iwdp's CSS domain may not be usable on the device without
   perturbing timing. On the device, N0 relies on the page-side census, which has no timing impact while nothing
   fires.
2. **MutationObserver cost.** It adds microtasks but no style work. It runs in the counts lane; in the timing lane
   and on the device it runs only as a final end-of-run check (the backstop hash).
3. **`cssVariables` skip option and React hydration attribute patching** are not verified here. S-AOT checks them.
4. **Blink `blink_style` category cost.** Assumed cheap, because the slices fire only on pending work. SPK-h (trace
   argument paths) should also check that these slices exist on the pinned headless-shell build.
5. **MUI upgrades.** A minor MUI release can add a lazily mounted styled child (as with the ripple). Every MUI
   version bump re-runs N0-N5 on all parts. That is why the MUI version belongs in the build ID.

---

## Sources

**Chromium** (`fcacb60bd396`, `third_party/blink/renderer/core/`):
- `css/css_style_sheet.cc` l.234-283, l.430-471
- `css/style_sheet_contents.cc` l.292-298, l.903-930
- `css/rule_set_diff.h` l.18-40
- `css/active_style_sheets.cc` l.75-149
- `css/style_engine.cc` l.152-200, l.440-460, l.672-680, l.893-899, l.1229-1329, l.1410-1454, l.2551-2700, l.2896-2938, l.3154-3325
- `css/css_font_selector.cc` l.159-165
- `css/style-invalidation.md` (via [03 §5.1])

**WebKit** (`77db40e2fa70`, `Source/WebCore/`):
- `css/CSSStyleSheet.cpp` l.204-268, l.373-392, l.644-671
- `style/StyleScope.cpp` l.168-176, l.498-537, l.555-650, l.690-760
- `style/StyleInvalidator.cpp` l.50-98, l.234-280, l.654-664
- `dom/InlineStyleSheetOwner.cpp` l.42-175
- `Source/JavaScriptCore/inspector/protocol/CSS.json` (events `styleSheetChanged`, `styleSheetAdded`, `styleSheetRemoved`)
- `testing/Internals.idl` l.1005-1008 (`styleRecalcCount`, `lastStyleUpdateSize`, `styleInvalidationTraversalCount`)

**npm packages** (`npm pack`, 2026-10-17):
- `@emotion/sheet@1.4.0` `src/index.ts` l.1-20, l.79, l.91-175
- `@emotion/cache@11.14.0` `src/index.ts` l.62-115, l.170-252
- `@emotion/react@11.14.0` `src/global.tsx` l.85-138
- `@emotion/use-insertion-effect-with-fallbacks` `src/index.ts`
- `@mui/styled-engine@9.5.0` `StyledEngineProvider/StyledEngineProvider.js` l.42-109
- `@mui/system@9.5.0` `cssVars/createCssVarsProvider.js` l.170-262
- `@mui/material@9.5.0`:
  - `ButtonBase/TouchRipple.js`, `ButtonBase/ButtonBase.js`, `useLazyRipple/useLazyRipple.js`;
  - `transitions/utils.js`, `Fade/Fade.js`, `Grow/Grow.js`, `Slide/Slide.js`, `Collapse/Collapse.js`;
  - `Tabs/Tabs.js`.
- `npm view @mui/material dist-tags` (latest 9.5.0, next 10.0.0-alpha.0) and `@mui/material@10.0.0-alpha.0 peerDependencies`.

**Docs:**
- https://svelte.dev/docs/svelte/svelte-compiler (`css`, `cssHash`)
- https://svelte.dev/docs/kit/configuration (`inlineStyleThreshold`)
- https://mui.com/material-ui/customization/css-layers/ (via [02 §5.1])

**Local:**
- `../fastwork-com-web-optimize/site-pretty/index.html`, `_app/immutable/assets/*.css`, `_app/immutable/{nodes,chunks}/*.js` (grep counts only; no code copied)

**Sibling notes:**
- `docs/plan/PLAN.md` rev 3
- `research/kickoff/02-site-anatomy-and-rewrite.md` §5
- `research/kickoff/03-chromium-rendering-math.md` §5.1
- `research/kickoff/04-webkit-rendering-math.md` §4.1, §9
- `research/kickoff/09-mui-zero-runtime/02-alternatives.md`
