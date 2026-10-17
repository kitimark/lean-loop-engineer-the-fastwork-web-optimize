---
id: 2026-10-17-css-decisions
kind: note
title: "M2 decisions: MUI cssVariables, and whether to add the dead CSS back as an inert stylesheet"
status: draft
created: 2026-10-17
topics: [styling, mui, n4, parity, m2-gate]
---

Draft for the user. Closes the M2 gate item "`cssVariables` and inert-dead-CSS decisions made" (PLAN §10.2).
Labels: CONFIRMED (source cited), MEASURED (counted here), INFERRED.

**Inputs.** Rewrite build: `apps/site/dist/aot` from worktree commit 2566949. Between that commit and HEAD 353d2f3,
only `engine.scroll/index.tsx` and two `part.json` files changed, and no CSS. Original: the 4 linked sheets under
`snapshot/site/_app/immutable/assets/` plus the 3 inline `<style>` tags in `snapshot/site/index.html`. I counted
statically with postcss 8.5.30 (script: scratchpad `n4/count.cjs`, not committed). The real N4 walks the CSSOM at the
end of W-rest, and N4 is not built yet: nothing under `packages/` or `apps/site/scripts` implements N0-N5. So treat
these numbers as estimates of N4.

## Static style shape today (MEASURED)

| | original (A) | rewrite (R), 4 pilots | of R: `mui.css` | of R: parts + reset |
|---|---|---|---|---|
| style rules | 1751 (1735 + 16 inline) | 791 | 739 | 52 |
| `@keyframes` | 128 | 0 | 0 | 0 |
| `@media` blocks | 92 (+2 inline) | 179 | 174 (80 `print`, 65 `hover:hover`, 26 `hover:none`, 3 `forced-colors`) | 5 |
| root custom properties (unique names) | **200** (384 decls in 22 `:where(:root),…` rules, `0.ChGpbVhU.css`) | **204**, all `--mui-*` | 204 | 0 |
| `--mui-*` root vars that some `var()` references | n/a | 60 of 204 (151 are palette) | | |
| `@property` / `@font-face` | 4 / 6 | 0 / 0 | | |

The pilot parts do not yet restate any of the original's 200 root tokens: that job belongs to the `theme.tokens` part,
which is not built. The census (`apps/site/src/Census.tsx`) renders the whole planned MUI component set, not only what
the pilots use. So R's ~739 MUI rules should stay about the same size as more parts land (INFERRED).

---

## Decision 1: `cssVariables` (rule S8, PLAN §6.5)

**Question.** Should the MUI theme emit its tokens as `:root` custom properties (`cssVariables: true`, the current
build), trim them, or not emit them at all (`false`)?

**What the pilots do now (CONFIRMED in code).**
- `createTheme({ cssVariables: true, colorSchemes: { light: true } })` (`apps/site/src/theme.ts:4-7`).
- `disableStyleSheetGeneration` is passed through an untyped cast (`apps/site/src/Root.tsx:7-8,18`).
- The variable sheet is serialised by our own `themeVariablesCss()` (`theme.ts:26-51`, called in
  `entry-server.tsx:91`).
- No part CSS reads a `--mui-*` variable: `grep var(--mui` over `src/parts/**/*.css` finds 0 (MEASURED).

**MUI facts (CONFIRMED, material-ui@1c3f8b4 = v9.5.0).**
- With only `light`, `colorSchemeSelector` defaults to `undefined` (`mui-material/src/styles/createThemeWithVars.js:135-138`).
  The provider's effect writes to `<html>` only when the selector is set and is not `'media'`
  (`mui-system/src/cssVars/createCssVarsProvider.tsx:353-395`). So the current setup writes nothing on `<html>`, as S8
  requires.
- `<GlobalStyles>` is skipped when `disableStyleSheetGeneration` is set **or** when `cssVariables === false`
  (`createCssVarsProvider.tsx:463-479`). With `false`, `ThemeProvider` takes the `ThemeProviderNoVars` path
  (`mui-material/src/styles/ThemeProvider.tsx:104-108`), so no `<Global>` exists at all.
- **Paper elevation:** in 9.5.0, Paper puts the shadow in an inline `--Paper-shadow` style whether or not variables are
  on. With variables off the value is the literal shadow (`mui-material/src/Paper/Paper.js:118-133`). So the main
  argument for `true` in [09.04] (an elevation change inserts no rule) holds for `false` too.
- Trimming exists: `shouldSkipGeneratingVar` is a theme option (`createThemeWithVars.js:135`; default list in
  `shouldSkipGeneratingVar.ts:1-14`).

**Why the root custom-property count matters for work (INFERRED from source).**
- *WebKit.* Every element's custom-property data keeps a pointer to the root's map ("Always reference the root style",
  `WebCore/style/computed/data/StyleCustomPropertyData.cpp:40-43` @862f17d). Equality checks can still loop over
  **all** properties, root ones included, when the two sides have different parents (`operator==`, l.98-127).
- That is the path a faithful part takes when it writes a variable on a subtree. `hero.exit` writes `--exit-opacity`
  this way. So each extra root variable can raise WebKit's per-element style cost in W-measure. This matches v1's
  `style_recalc_var` at 2.2× the blank-page cost on WebKit (OBSERVED-v1, [03 §5.1]).
- *Blink.* `StyleVariables` is a hash trie with structural sharing, and equality short-circuits on hashes
  (`blink/renderer/core/style/style_variables.h` and `style_variables.cc:11-30` @f842f52). The count matters less there.

**Options and their effect on parity.**

| Option | N4 root vars (A = 200) | Breakpoint gate (PL0-PL2) | N0/N1/N5 | N2/N3, PL5 counts | Code |
|---|---|---|---|---|---|
| **a. `true`, untrimmed (today)** | ≈ 200 tokens + 204 = **~404, about 2×**: outside ±10 %, so N4 flags every part for PL6 | no effect: the gate compares each role's declared, non-custom properties (`gate-breakpoints/src/page.mjs:144-150`) (INFERRED) | 0 risk while the cast and the static sheet hold | Blink: none expected. WebKit: higher per-element cost on subtree variable writes (above). Counts cannot see this, so PL5 passes while PL6 may not | keeps the untyped cast and our serialiser (glue that has to stay right) |
| **b. `true`, trimmed to referenced** | ≈ 200 + 60 = **~260, +30 %**: still outside ±10 % | same as a | same as a | smaller version of a | adds a skip predicate that has to track the census |
| **c. `false`** | ≈ **200**: within ±10 % once `theme.tokens` lands | same as a | no `<Global>` at all (`ThemeProviderNoVars`) | no extra inherited variables. Paper and AppBar elevation still insert nothing (Paper.js above) | drops the cast, `themeVariablesCss()` and the `themeCss` slot. MUI rules carry literal values |

**Recommendation: c, `cssVariables: false`.** Reasons:
- Nothing reads the variables today.
- The one benefit [09.04] measured for `true` (no insertion when elevation changes) also holds with `false` in 9.5.0.
- It is the only option that keeps N4's root custom-property count within ±10 % of arm A.
- It removes the WebKit inherited-variable bias at its source instead of carrying it into PL6.

[09 README] already allows this ("`cssVariables: false` if N4 finds too many root custom properties"). The static
count above (2×) is that finding, ahead of a CSSOM N4.

**Check before landing (one build, about 0.5 h, part of the flip PR):**
- rebuild aot with `false`;
- census 0 misses;
- 0 `<style data-emotion>`;
- the breakpoint gate core matrix still green;
- `:root` `--mui-*` count = 0;
- `mui.css` rule count within a few rules of 739 (INFERRED: the same rules, now with literal values).

**Needs your call:** flip S8's default from `true` to `false`. It is a plan rule, and [09] leaned to `true`.

---

## Decision 2: inert dead CSS (PLAN §6.1, last paragraph)

**Question.** The original ships rules that no element ever matches (the Platform `paid-*`, `quote-*`,
`service-card`, `agents-*` families and others, [02 §2.6]). Should the `faithful` preset add them back as a restated
**inert stylesheet** with the same rule count, so that per-element style cost matches?

**What the pilots do now (CONFIRMED in code).**
- No pilot ports dead CSS. The parts' CSS has 0 `@keyframes` and 0 `@property`. The hero's dead `.hero-cta:before`
  orbit `@property` animation (F-015, [02 §2.2]) is not restated.
- All four pilots are outside Platform, so they contain no Platform dead CSS anyway.
- Per PLAN §6.6, all 4 pilots pass all 14 cells in both engines (MEASURED, e7fb102). `engine.scroll` and
  `nav.hitTest` are NC because they have no styled anchors.

**How big the dead set is (MEASURED, a rough estimate).**
- Rules whose every selector matches the [02 §2.6] family names: 141 of 1735 style rules (8 %), 611 of 7510
  declarations, and 42 of 128 `@keyframes`.
- 5 `@media (prefers-reduced-motion:reduce)` blocks contain only such rules.
- These are name matches, not a verified dead list. They miss families [02] names only loosely ("orbit swap", …). They
  also catch possibly live rules such as `.start-selling-platform-service-card-row img`.
- An exact set needs a coverage pass: a rule is dead if its selector matches no element in any captured state of any
  scenario.

**Why unmatched rules cost almost nothing per element (CONFIRMED mechanism, INFERRED for size).**
- Both engines file a rule under the class of its rightmost compound selector. Blink: `rule_set.cc:703` @f842f52.
  WebKit: `RuleSet.cpp:428` @862f17d.
- They then look up only the buckets for classes the element actually has. Blink: `element_rule_collector.cc:875-878`.
  WebKit: `ElementRuleCollector.cpp:241-242`.
- 153 of the 167 dead selectors are class-keyed (MEASURED). Rules for classes no element carries are never tried, and
  their invalidation sets never fire. An unused `@keyframes` costs nothing per frame.
- So the dead rules cost parse time and RuleSet build time in **W-load** (class X by the N0 rule), plus a little for
  the 14 tag-keyed selectors. They cost about nothing in W-measure.

**Options and their effect on parity.**

| Option | N4 rule count (A ≈ 1751) | Breakpoint gate and lint | N0-N3, PL5 counts | Cost |
|---|---|---|---|---|
| **a. Do not port (today)** | ≈ 739 MUI + ≈ 1600 restated live ≈ **~2300, +30 %** (INFERRED projection). R already has more rules than A because the MUI census is mostly unmatched rules too | PL0-PL2 compare matched styles only, so no effect. The lint compares condition **sets**; the 5 dead-only reduced-motion blocks drop the block count but not the set if the part has other reduced-motion rules (INFERRED) | no effect in W-measure | none |
| **b. Inert sheet, same rule count** | ≈ **~2450, +40 %**: further from A, the opposite of the aim | must exclude its `@media` from the lint, or it becomes a lint input | W-load parse goes up (class X). W-measure: no change (mechanism above) | restating about 140-1000 rules by hand, a time-box risk (R8) |
| **c. Inert sheet sized to equalise N4** | would need *negative* rules: not possible | | | |

**Recommendation: a.** Do not add an inert stylesheet. Record the N4 rule-count difference as a K-fixture parameter,
as §12.3 already recommends for N4. The premise in §6.1 was that R would be *short* of rules and an inert sheet would
top it up. That premise no longer holds: MUI's static census already puts R above A. Two more reasons:
- Per-element matching does not see unmatched class-keyed rules in either engine.
- The original's dead rules belong to W-load, which N0 already treats as class X.

Two refinements, so N4 can tell shape from noise:
1. Split N4's rule count into *all* rules and *reachable* rules: rules whose rightmost-compound class, id or tag
   exists in the DOM at the end of W-rest.
2. Mark a coverage-derived dead list in the inventory, so the breakpoint lint does not ask for conditions that only
   dead rules use.

**Revisit if** K10 or PL6 shows that W-load stylesheet size moves the first-scroll frames (§4.6 rest 6 s + first
scroll). Then the inert sheet comes back as a separate W-load experiment arm, never part of `faithful`.

**Needs your call:** confirm that `faithful` means "what runs" ([02 §0] point 1: "reproduce only what runs"), so the
§6.1 "inert stylesheet" option is dropped rather than kept open.

---

## What this changes in the plan

| Section | Change |
|---|---|
| §6.5 S8 | "`cssVariables: true` with `disableStyleSheetGeneration` …" becomes "`cssVariables: false` (no `:root` `--mui-*`, no `<Global>`; Paper elevation stays an inline variable, Paper.js l.118-133 @9.5.0); `true` only with a written reason and N4 within ±10 %" |
| §6.1, last paragraph | replace the inert-stylesheet option with "dead CSS is not ported; N4's rule-count difference is a K-fixture parameter; an inert-sheet arm only if K10/PL6 shows W-load size matters" |
| §6.7 N4 | add "rules split into all and reachable (rightmost compound present in the DOM)"; note the static estimate: A 1751 rules / 200 root vars, R today 791 / 204 |
| §6.6 breakpoint lint | the inventory marks coverage-derived dead rules, and the lint ignores conditions used only by them |
| §10.2 M2 | tick "`cssVariables` and inert-dead-CSS decisions made" once you accept both, and land the flip PR (S8) with the build check above |
| §12.3 | add row: "Inert dead-CSS sheet → dropped (rules unmatched per element; R already above A from the MUI census)" |
| apps/site (glue) | the flip PR removes the `disableStyleSheetGeneration` cast (`Root.tsx:7-8`), `themeVariablesCss()` (`theme.ts:23-51`) and the `themeCss` slot (`entry-server.tsx:91`) |
